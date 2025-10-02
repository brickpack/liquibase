FROM eclipse-temurin:17-jre-alpine

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    curl \
    wget \
    jq \
    git \
    postgresql-client \
    mysql-client \
    unzip \
    libaio \
    libnsl \
    libc6-compat

# Install Oracle Instant Client
RUN mkdir -p /opt/oracle && cd /opt/oracle \
    && wget -q https://download.oracle.com/otn_software/linux/instantclient/2340000/instantclient-basiclite-linux.x64-23.4.0.24.05.zip \
    && wget -q https://download.oracle.com/otn_software/linux/instantclient/2340000/instantclient-sqlplus-linux.x64-23.4.0.24.05.zip \
    && unzip -oq instantclient-basiclite-linux.x64-23.4.0.24.05.zip \
    && unzip -oq instantclient-sqlplus-linux.x64-23.4.0.24.05.zip \
    && rm -f *.zip \
    && find /opt/oracle/instantclient_23_4 -name "*.sym" -delete

ENV PATH="/opt/oracle/instantclient_23_4:${PATH}" \
    LD_LIBRARY_PATH="/opt/oracle/instantclient_23_4"

# Install SQL Server tools (using static binary approach for Alpine)
RUN wget -q https://packages.microsoft.com/config/ubuntu/22.04/prod.list -O /tmp/mssql.list \
    && apk add --no-cache --virtual .build-deps gnupg \
    && mkdir -p /opt/mssql-tools \
    && cd /opt/mssql-tools \
    && wget -q https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/msodbcsql18_18.3.1.1-1_amd64.apk \
    && wget -q https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/mssql-tools18_18.3.1.1-1_amd64.apk \
    && apk add --allow-untrusted msodbcsql18_18.3.1.1-1_amd64.apk \
    && apk add --allow-untrusted mssql-tools18_18.3.1.1-1_amd64.apk \
    && rm -f *.apk \
    && apk del .build-deps \
    && rm -rf /tmp/*

ENV PATH="/opt/mssql-tools18/bin:${PATH}"

# Install Liquibase and JDBC drivers in a single layer
ENV LIQUIBASE_VERSION=4.33.0
RUN wget -q https://github.com/liquibase/liquibase/releases/download/v${LIQUIBASE_VERSION}/liquibase-${LIQUIBASE_VERSION}.tar.gz \
    && mkdir -p /opt/liquibase \
    && tar -xzf liquibase-${LIQUIBASE_VERSION}.tar.gz -C /opt/liquibase \
    && rm liquibase-${LIQUIBASE_VERSION}.tar.gz \
    && chmod +x /opt/liquibase/liquibase \
    && mkdir -p /opt/liquibase/lib \
    && wget -q -O /opt/liquibase/lib/postgresql.jar https://jdbc.postgresql.org/download/postgresql-42.7.4.jar \
    && wget -q -O /opt/liquibase/lib/mysql-connector-j.jar https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/9.1.0/mysql-connector-j-9.1.0.jar \
    && wget -q -O /opt/liquibase/lib/ojdbc11.jar https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc11/23.6.0.24.10/ojdbc11-23.6.0.24.10.jar \
    && wget -q -O /opt/liquibase/lib/mssql-jdbc.jar https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/12.8.1.jre11/mssql-jdbc-12.8.1.jre11.jar \
    && rm -f /opt/liquibase/internal/lib/mssql-jdbc*.jar \
    && rm -f /opt/liquibase/internal/lib/postgresql*.jar \
    && rm -f /opt/liquibase/internal/lib/ojdbc*.jar \
    && rm -f /opt/liquibase/internal/lib/mysql-connector*.jar

ENV PATH="/opt/liquibase:${PATH}"

# Install AWS CLI v2 using pip (Alpine-compatible method)
RUN apk add --no-cache python3 py3-pip \
    && pip3 install --no-cache-dir --break-system-packages awscli \
    && aws --version

WORKDIR /workspace

CMD ["/bin/bash"]
