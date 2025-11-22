
#!/usr/bin/env bash
set -euo pipefail

# mssql_setup.sh.tpl
# Description: This template is rendered into EC2 `user_data` and executed
# on first boot. It installs Microsoft SQL Server on Ubuntu, creates three
# databases and filegroups, sets recovery models, creates server logins and
# database users, and attempts to clone/run Bitbucket post-deploy scripts.

# --- Templated variables (substituted by `templatefile`) ---
SA_PASSWORD="${sa_password}"
SQL_ADM_S_PW="${adm_password}"
SQL_DEV_R_PW="${dev_r_password}"
SQL_DEV_W_PW="${dev_w_password}"
BB_REPO="${bitbucket_repo}"
BB_USER="${bitbucket_user}"
BB_APP_PASS="${bitbucket_app_pass}"

export DEBIAN_FRONTEND=noninteractive

echo "[1/8] Updating apt and installing dependencies"
# Install tools required to add Microsoft package repos and to clone git repos
apt-get update -y
apt-get install -y curl apt-transport-https gnupg lsb-release ca-certificates software-properties-common git

echo "[2/8] Registering Microsoft repos for SQL Server"
# Add Microsoft package signing key and apt sources for SQL Server and tools
curl -sSL https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
curl -sSL https://packages.microsoft.com/config/ubuntu/22.04/mssql-server-2022.list | tee /etc/apt/sources.list.d/mssql-server.list
curl -sSL https://packages.microsoft.com/config/ubuntu/22.04/prod.list | tee /etc/apt/sources.list.d/msprod.list
apt-get update -y

echo "[3/8] Installing SQL Server"
# Install SQL Server non-interactively using the provided SA password
ACCEPT_EULA=Y MSSQL_SA_PASSWORD="$SA_PASSWORD" apt-get install -y mssql-server

echo "[4/8] Configure SQL Server (non-interactive)"
# Run mssql-conf setup in non-interactive mode using environment variables
MSSQL_SA_PASSWORD="$SA_PASSWORD" ACCEPT_EULA=Y /opt/mssql/bin/mssql-conf -n setup

echo "[5/8] Installing mssql-tools for sqlcmd"
# Install command-line tools (sqlcmd) and ensure the path is available
apt-get install -y mssql-tools unixodbc-dev
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' > /etc/profile.d/mssql-tools.sh
chmod +x /etc/profile.d/mssql-tools.sh
source /etc/profile.d/mssql-tools.sh || true

echo "[6/8] Waiting for SQL Server to be ready"
# Give SQL Server a short time to accept connections before running sqlcmd
sleep 15

SQLFILE=/tmp/create_databases.sql

# Create the SQL script that will create databases, filegroups, files
# and server/database-level users. The script is idempotent: it checks for
# existence before creating objects.
cat > "$SQLFILE" <<'SQL'
-- Create server logins (if they don't already exist)
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'SQL_ADM_S')
  CREATE LOGIN [SQL_ADM_S] WITH PASSWORD = N'${SQL_ADM_S_PW}';
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'SQL_DEV_R')
  CREATE LOGIN [SQL_DEV_R] WITH PASSWORD = N'${SQL_DEV_R_PW}';
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'SQL_DEV_W')
  CREATE LOGIN [SQL_DEV_W] WITH PASSWORD = N'${SQL_DEV_W_PW}';

-- ********** DEV database **********
IF DB_ID(N'dev') IS NULL
BEGIN
  CREATE DATABASE [dev]
  ON PRIMARY
    (NAME = N'dev_pri', FILENAME = N'/var/opt/mssql/data/dev_pri.mdf', SIZE = 10MB)
  LOG ON
    (NAME = N'dev_log', FILENAME = N'/var/opt/mssql/data/dev_log.ldf', SIZE = 20MB);
  -- Add two logical filegroups named 'mdf' and 'ldf'
  ALTER DATABASE [dev] ADD FILEGROUP [mdf];
  ALTER DATABASE [dev] ADD FILEGROUP [ldf];
  -- Add additional files to the filegroups (NDF files)
  ALTER DATABASE [dev] ADD FILE (NAME = N'dev_mdf1', FILENAME = N'/var/opt/mssql/data/dev_mdf1.ndf', SIZE = 50MB) TO FILEGROUP [mdf];
  ALTER DATABASE [dev] ADD FILE (NAME = N'dev_ldf1', FILENAME = N'/var/opt/mssql/data/dev_ldf1.ndf', SIZE = 50MB) TO FILEGROUP [ldf];
END
-- Set requested recovery model
ALTER DATABASE [dev] SET RECOVERY FULL;

-- ********** DEV_DATA database **********
IF DB_ID(N'dev_data') IS NULL
BEGIN
  CREATE DATABASE [dev_data]
  ON PRIMARY
    (NAME = N'dev_data_pri', FILENAME = N'/var/opt/mssql/data/dev_data_pri.mdf', SIZE = 10MB)
  LOG ON
    (NAME = N'dev_data_log', FILENAME = N'/var/opt/mssql/data/dev_data_log.ldf', SIZE = 20MB);
  ALTER DATABASE [dev_data] ADD FILEGROUP [mdf];
  ALTER DATABASE [dev_data] ADD FILEGROUP [ldf];
  ALTER DATABASE [dev_data] ADD FILE (NAME = N'dev_data_mdf1', FILENAME = N'/var/opt/mssql/data/dev_data_mdf1.ndf', SIZE = 50MB) TO FILEGROUP [mdf];
  ALTER DATABASE [dev_data] ADD FILE (NAME = N'dev_data_ldf1', FILENAME = N'/var/opt/mssql/data/dev_data_ldf1.ndf', SIZE = 50MB) TO FILEGROUP [ldf];
END
ALTER DATABASE [dev_data] SET RECOVERY SIMPLE;

-- ********** DEV_S database **********
IF DB_ID(N'dev_s') IS NULL
BEGIN
  CREATE DATABASE [dev_s]
  ON PRIMARY
    (NAME = N'dev_s_pri', FILENAME = N'/var/opt/mssql/data/dev_s_pri.mdf', SIZE = 10MB)
  LOG ON
    (NAME = N'dev_s_log', FILENAME = N'/var/opt/mssql/data/dev_s_log.ldf', SIZE = 20MB);
  ALTER DATABASE [dev_s] ADD FILEGROUP [mdf];
  ALTER DATABASE [dev_s] ADD FILEGROUP [ldf];
  ALTER DATABASE [dev_s] ADD FILE (NAME = N'dev_s_mdf1', FILENAME = N'/var/opt/mssql/data/dev_s_mdf1.ndf', SIZE = 50MB) TO FILEGROUP [mdf];
  ALTER DATABASE [dev_s] ADD FILE (NAME = N'dev_s_ldf1', FILENAME = N'/var/opt/mssql/data/dev_s_ldf1.ndf', SIZE = 50MB) TO FILEGROUP [ldf];
END
ALTER DATABASE [dev_s] SET RECOVERY SIMPLE;

-- Create users inside each database and assign roles
-- Role mapping:
--   SQL_ADM_S = db_datareader (Read-only)
--   SQL_DEV_R = db_datareader (Read-only)
--   SQL_DEV_W = db_datareader + db_datawriter (Read & Write)

DECLARE @db_name sysname;
DECLARE db_cursor CURSOR FOR
SELECT name FROM sys.databases WHERE name IN ('dev','dev_data','dev_s');
OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db_name;
WHILE @@FETCH_STATUS = 0
BEGIN
  DECLARE @sql NVARCHAR(MAX) = N'';
  SET @sql = N'USE [' + @db_name + N'];\n'
    + N'IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N''SQL_ADM_S'') CREATE USER [SQL_ADM_S] FOR LOGIN [SQL_ADM_S];\n'
    + N'IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N''SQL_DEV_R'') CREATE USER [SQL_DEV_R] FOR LOGIN [SQL_DEV_R];\n'
    + N'IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N''SQL_DEV_W'') CREATE USER [SQL_DEV_W] FOR LOGIN [SQL_DEV_W];\n'
    + N'EXEC sp_addrolemember N''db_datareader'', N''SQL_ADM_S'';\n'
    + N'EXEC sp_addrolemember N''db_datareader'', N''SQL_DEV_R'';\n'
    + N'EXEC sp_addrolemember N''db_datareader'', N''SQL_DEV_W'';\n'
    + N'EXEC sp_addrolemember N''db_datawriter'', N''SQL_DEV_W'';\n';
  EXEC sp_executesql @sql;
  FETCH NEXT FROM db_cursor INTO @db_name;
END
CLOSE db_cursor;
DEALLOCATE db_cursor;

SQL

echo "[7/8] Running SQL script to create databases and users"
# Execute the generated SQL file via sqlcmd using SA credentials
/opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -i "$SQLFILE"

echo "[8/8] Cloning Bitbucket repo and running scripts (placeholder)"
# Attempt to clone Bitbucket repo over HTTPS using app password (not recommended for prod)
BB_CLONE_URL="$BB_REPO"
if [ -n "$BB_USER" ] && [ -n "$BB_APP_PASS" ]; then
  # NOTE: embedding credentials in the URL is insecure and should be replaced
  # with SSH deploy keys or a more secure mechanism in production.
  BB_CLONE_URL="${BB_CLONE_URL/https:\/\//https:\/\/$BB_USER:$BB_APP_PASS@}"
fi

cd /home/ubuntu || cd /root || true
git clone "$BB_CLONE_URL" bitbucket-scripts || echo "Clone failed or already exists"
if [ -d bitbucket-scripts ]; then
  cd bitbucket-scripts
  # Placeholder execution: runs `run-after-db.sh` if present in repo
  if [ -f run-after-db.sh ]; then
    chmod +x run-after-db.sh
    ./run-after-db.sh || echo "run-after-db.sh exited non-zero"
  else
    echo "No run-after-db.sh found in repo; adjust template as needed"
  fi
fi

echo "SQL Server provisioning complete"

#!/usr/bin/env bash
set -euo pipefail

# Variables substituted by Terraform templatefile
SA_PASSWORD="${sa_password}"
SQL_ADM_S_PW="${adm_password}"
SQL_DEV_R_PW="${dev_r_password}"
SQL_DEV_W_PW="${dev_w_password}"
BB_REPO="${bitbucket_repo}"
BB_USER="${bitbucket_user}"
BB_APP_PASS="${bitbucket_app_pass}"

export DEBIAN_FRONTEND=noninteractive

echo "[1/8] Updating apt and installing dependencies"
apt-get update -y
apt-get install -y curl apt-transport-https gnupg lsb-release ca-certificates software-properties-common git

echo "[2/8] Registering Microsoft repos for SQL Server"
curl -sSL https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
curl -sSL https://packages.microsoft.com/config/ubuntu/22.04/mssql-server-2022.list | tee /etc/apt/sources.list.d/mssql-server.list
curl -sSL https://packages.microsoft.com/config/ubuntu/22.04/prod.list | tee /etc/apt/sources.list.d/msprod.list
apt-get update -y

echo "[3/8] Installing SQL Server"
ACCEPT_EULA=Y MSSQL_SA_PASSWORD="$SA_PASSWORD" apt-get install -y mssql-server

echo "[4/8] Configure SQL Server (non-interactive)"
MSSQL_SA_PASSWORD="$SA_PASSWORD" ACCEPT_EULA=Y /opt/mssql/bin/mssql-conf -n setup

echo "[5/8] Installing mssql-tools for sqlcmd"
apt-get install -y mssql-tools unixodbc-dev
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' > /etc/profile.d/mssql-tools.sh
chmod +x /etc/profile.d/mssql-tools.sh
source /etc/profile.d/mssql-tools.sh || true

echo "[6/8] Waiting for SQL Server to be ready"
sleep 15

SQLFILE=/tmp/create_databases.sql
cat > "$SQLFILE" <<'SQL'
-- Create server logins (if they don't already exist)
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'SQL_ADM_S')
  CREATE LOGIN [SQL_ADM_S] WITH PASSWORD = N'${SQL_ADM_S_PW}';
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'SQL_DEV_R')
  CREATE LOGIN [SQL_DEV_R] WITH PASSWORD = N'${SQL_DEV_R_PW}';
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'SQL_DEV_W')
  CREATE LOGIN [SQL_DEV_W] WITH PASSWORD = N'${SQL_DEV_W_PW}';

-- ********** DEV database **********
IF DB_ID(N'dev') IS NULL
BEGIN
  CREATE DATABASE [dev]
  ON PRIMARY
    (NAME = N'dev_pri', FILENAME = N'/var/opt/mssql/data/dev_pri.mdf', SIZE = 10MB)
  LOG ON
    (NAME = N'dev_log', FILENAME = N'/var/opt/mssql/data/dev_log.ldf', SIZE = 20MB);
  ALTER DATABASE [dev] ADD FILEGROUP [mdf];
  ALTER DATABASE [dev] ADD FILEGROUP [ldf];
  ALTER DATABASE [dev] ADD FILE (NAME = N'dev_mdf1', FILENAME = N'/var/opt/mssql/data/dev_mdf1.ndf', SIZE = 50MB) TO FILEGROUP [mdf];
  ALTER DATABASE [dev] ADD FILE (NAME = N'dev_ldf1', FILENAME = N'/var/opt/mssql/data/dev_ldf1.ndf', SIZE = 50MB) TO FILEGROUP [ldf];
END
ALTER DATABASE [dev] SET RECOVERY FULL;

-- ********** DEV_DATA database **********
IF DB_ID(N'dev_data') IS NULL
BEGIN
  CREATE DATABASE [dev_data]
  ON PRIMARY
    (NAME = N'dev_data_pri', FILENAME = N'/var/opt/mssql/data/dev_data_pri.mdf', SIZE = 10MB)
  LOG ON
    (NAME = N'dev_data_log', FILENAME = N'/var/opt/mssql/data/dev_data_log.ldf', SIZE = 20MB);
  ALTER DATABASE [dev_data] ADD FILEGROUP [mdf];
  ALTER DATABASE [dev_data] ADD FILEGROUP [ldf];
  ALTER DATABASE [dev_data] ADD FILE (NAME = N'dev_data_mdf1', FILENAME = N'/var/opt/mssql/data/dev_data_mdf1.ndf', SIZE = 50MB) TO FILEGROUP [mdf];
  ALTER DATABASE [dev_data] ADD FILE (NAME = N'dev_data_ldf1', FILENAME = N'/var/opt/mssql/data/dev_data_ldf1.ndf', SIZE = 50MB) TO FILEGROUP [ldf];
END
ALTER DATABASE [dev_data] SET RECOVERY SIMPLE;

-- ********** DEV_S database **********
IF DB_ID(N'dev_s') IS NULL
BEGIN
  CREATE DATABASE [dev_s]
  ON PRIMARY
    (NAME = N'dev_s_pri', FILENAME = N'/var/opt/mssql/data/dev_s_pri.mdf', SIZE = 10MB)
  LOG ON
    (NAME = N'dev_s_log', FILENAME = N'/var/opt/mssql/data/dev_s_log.ldf', SIZE = 20MB);
  ALTER DATABASE [dev_s] ADD FILEGROUP [mdf];
  ALTER DATABASE [dev_s] ADD FILEGROUP [ldf];
  ALTER DATABASE [dev_s] ADD FILE (NAME = N'dev_s_mdf1', FILENAME = N'/var/opt/mssql/data/dev_s_mdf1.ndf', SIZE = 50MB) TO FILEGROUP [mdf];
  ALTER DATABASE [dev_s] ADD FILE (NAME = N'dev_s_ldf1', FILENAME = N'/var/opt/mssql/data/dev_s_ldf1.ndf', SIZE = 50MB) TO FILEGROUP [ldf];
END
ALTER DATABASE [dev_s] SET RECOVERY SIMPLE;

-- Create users inside each database and assign roles
-- SQL_ADM_S = Read-only
-- SQL_DEV_R = Read-only
-- SQL_DEV_W = Read & Write

DECLARE @db_name sysname;
DECLARE db_cursor CURSOR FOR
SELECT name FROM sys.databases WHERE name IN ('dev','dev_data','dev_s');
OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db_name;
WHILE @@FETCH_STATUS = 0
BEGIN
  DECLARE @sql NVARCHAR(MAX) = N'';
  SET @sql = N'USE [' + @db_name + N'];\n'
    + N'IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N''SQL_ADM_S'') CREATE USER [SQL_ADM_S] FOR LOGIN [SQL_ADM_S];\n'
    + N'IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N''SQL_DEV_R'') CREATE USER [SQL_DEV_R] FOR LOGIN [SQL_DEV_R];\n'
    + N'IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N''SQL_DEV_W'') CREATE USER [SQL_DEV_W] FOR LOGIN [SQL_DEV_W];\n'
    + N'EXEC sp_addrolemember N''db_datareader'', N''SQL_ADM_S'';\n'
    + N'EXEC sp_addrolemember N''db_datareader'', N''SQL_DEV_R'';\n'
    + N'EXEC sp_addrolemember N''db_datareader'', N''SQL_DEV_W'';\n'
    + N'EXEC sp_addrolemember N''db_datawriter'', N''SQL_DEV_W'';\n';
  EXEC sp_executesql @sql;
  FETCH NEXT FROM db_cursor INTO @db_name;
END
CLOSE db_cursor;
DEALLOCATE db_cursor;

SQL

echo "[7/8] Running SQL script to create databases and users"
/opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -i "$SQLFILE"

echo "[8/8] Cloning Bitbucket repo and running scripts (placeholder)"
# This uses HTTPS with app-password; replace with SSH/deploy key if preferred
BB_CLONE_URL="$BB_REPO"
if [ -n "$BB_USER" ] && [ -n "$BB_APP_PASS" ]; then
  # Insert credentials into URL for non-interactive clone (note: visible in process args, update to SSH deploy-key in production)
  BB_CLONE_URL="${BB_CLONE_URL/https:\/\//https:\/\/$BB_USER:$BB_APP_PASS@}"
fi

cd /home/ubuntu || cd /root || true
git clone "$BB_CLONE_URL" bitbucket-scripts || echo "Clone failed or already exists"
if [ -d bitbucket-scripts ]; then
  cd bitbucket-scripts
  # Run scripts - placeholder: user should adapt to their scripts
  if [ -f run-after-db.sh ]; then
    chmod +x run-after-db.sh
    ./run-after-db.sh || echo "run-after-db.sh exited non-zero"
  else
    echo "No run-after-db.sh found in repo; adjust template as needed"
  fi
fi

echo "SQL Server provisioning complete"
