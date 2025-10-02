FROM ubuntu:24.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install all dependencies in a single layer to reduce image size
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    gnupg \
    ca-certificates \
    unzip \
    jq \
    git \
    openjdk-17-jre-headless \
    postgresql-client \
    mysql-client \
    libaio1t64 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install Oracle Instant Client (using basiclite for smaller size)
RUN mkdir -p /opt/oracle && cd /opt/oracle \
    && wget -q https://download.oracle.com/otn_software/linux/instantclient/2340000/instantclient-basiclite-linux.x64-23.4.0.24.05.zip \
    && wget -q https://download.oracle.com/otn_software/linux/instantclient/2340000/instantclient-sqlplus-linux.x64-23.4.0.24.05.zip \
    && unzip -oq instantclient-basiclite-linux.x64-23.4.0.24.05.zip \
    && unzip -oq instantclient-sqlplus-linux.x64-23.4.0.24.05.zip \
    && rm -f *.zip \
    && find /opt/oracle/instantclient_23_4 -name "*.sym" -delete \
    && echo /opt/oracle/instantclient_23_4 > /etc/ld.so.conf.d/oracle-instantclient.conf \
    && ldconfig

# Set Oracle environment variables
ENV PATH="/opt/oracle/instantclient_23_4:${PATH}"
ENV LD_LIBRARY_PATH="/opt/oracle/instantclient_23_4"

# Install SQL Server command-line tools
RUN curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && curl https://packages.microsoft.com/config/ubuntu/24.04/prod.list | tee /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y mssql-tools18 unixodbc-dev \
    && rm -rf /var/lib/apt/lists/*

# Add SQL Server tools to PATH
ENV PATH="/opt/mssql-tools18/bin:${PATH}"

# Install Liquibase
ENV LIQUIBASE_VERSION=4.33.0
RUN wget -q https://github.com/liquibase/liquibase/releases/download/v${LIQUIBASE_VERSION}/liquibase-${LIQUIBASE_VERSION}.tar.gz \
    && mkdir -p /opt/liquibase \
    && tar -xzf liquibase-${LIQUIBASE_VERSION}.tar.gz -C /opt/liquibase \
    && rm liquibase-${LIQUIBASE_VERSION}.tar.gz \
    && chmod +x /opt/liquibase/liquibase

# Add Liquibase to PATH
ENV PATH="/opt/liquibase:${PATH}"

# Install JDBC drivers
RUN mkdir -p /opt/liquibase/lib \
    && wget -q -O /opt/liquibase/lib/postgresql.jar https://jdbc.postgresql.org/download/postgresql-42.7.4.jar \
    && wget -q -O /opt/liquibase/lib/mysql-connector-j.jar https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/9.1.0/mysql-connector-j-9.1.0.jar \
    && wget -q -O /opt/liquibase/lib/ojdbc11.jar https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc11/23.6.0.24.10/ojdbc11-23.6.0.24.10.jar \
    && wget -q -O /opt/liquibase/lib/mssql-jdbc.jar https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/12.8.1.jre11/mssql-jdbc-12.8.1.jre11.jar

# Install AWS CLI v2
RUN curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# Set working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
