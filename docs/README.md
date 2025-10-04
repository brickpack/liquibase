# Liquibase CI/CD Documentation

Complete documentation for managing database changes with Liquibase, GitHub Actions, and AWS Secrets Manager.

---

## Getting Started

**New to this project?** Start here:

1. **[SETUP.md](SETUP.md)** - Complete setup guide
   - AWS IAM configuration
   - Secrets Manager setup
   - Database-specific configuration (PostgreSQL, MySQL, SQL Server, Oracle)
   - First database creation
   - Local development setup

---

## Core Documentation

### [USER-MANAGEMENT.md](USER-MANAGEMENT.md)
Database user creation and password management.

**Topics:**
- Two-step user creation approach
- Temporary vs real passwords
- Password rotation
- Platform-specific examples
- Troubleshooting

---

### [WORKFLOW-GUIDE.md](WORKFLOW-GUIDE.md)
Understanding and using the CI/CD pipeline.

**Topics:**
- Test mode vs Deploy mode
- When each mode runs
- Best practices for PostgreSQL, SQL Server, MySQL, Oracle
- Changeset organization
- Common scenarios
- Performance tips
- Comprehensive troubleshooting

---

### [REFERENCE.md](REFERENCE.md)
Technical reference for advanced topics.

**Topics:**
- Docker container details
- Secrets management architecture
- Helper scripts documentation
- Advanced configuration
- Security considerations

---

## Quick Links

### Common Tasks

- **Create a new server secret**: [SETUP.md § Create Secrets](SETUP.md#2-aws-secrets-manager-setup)
- **Add a database**: [SETUP.md § Create Your First Database](SETUP.md#5-create-your-first-database)
- **Manage users**: [USER-MANAGEMENT.md](USER-MANAGEMENT.md)
- **Understand test vs deploy**: [WORKFLOW-GUIDE.md § Workflow Modes](WORKFLOW-GUIDE.md#workflow-modes)
- **Troubleshoot issues**: [WORKFLOW-GUIDE.md § Troubleshooting](WORKFLOW-GUIDE.md#troubleshooting)
- **Use helper scripts**: [REFERENCE.md § Helper Scripts](REFERENCE.md#helper-scripts)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     GitHub Actions Workflow                      │
│                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐   │
│  │  Test Mode   │     │ Deploy Mode  │     │   Manual     │   │
│  │  (Branches)  │────▶│    (Main)    │────▶│   Trigger    │   │
│  └──────────────┘     └──────────────┘     └──────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │   AWS Secrets Manager │
                    │                       │
                    │  Per-Server Secrets:  │
                    │  - liquibase-postgres-prod │
                    │  - liquibase-mysql-prod    │
                    │  - liquibase-sqlserver-prod│
                    │  - liquibase-oracle-prod   │
                    └───────────────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │     Your Databases    │
                    │                       │
                    │  - Creates databases  │
                    │  - Applies changesets │
                    │  - Manages users      │
                    └───────────────────────┘
```

---

## Documentation Philosophy

- **Setup Guide**: Get up and running quickly
- **User Management**: Specific feature documentation
- **Workflow Guide**: How to use the pipeline effectively + best practices
- **Reference**: Deep dive into architecture and advanced topics

---

## Need Help?

1. **Check the docs** - Most questions are answered in one of the guides above
2. **Read error messages** - The pipeline provides detailed error messages
3. **Check workflow logs** - GitHub Actions logs show exactly what happened
4. **Review the troubleshooting sections** - Common issues and solutions

---

## Contributing to Documentation

When updating documentation:

1. Keep it concise and actionable
2. Use examples liberally
3. Add to the appropriate guide:
   - **SETUP.md** - Initial configuration and setup steps
   - **USER-MANAGEMENT.md** - User-related features
   - **WORKFLOW-GUIDE.md** - Workflow behavior and best practices
   - **REFERENCE.md** - Technical details and advanced topics
