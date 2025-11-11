#!/bin/bash
# APEX Export to Git
# Exit on error for critical commands
set -o pipefail

STR_CONN=$1
WORK_DIR=$2
CONFIG_FILE=$3

# Load configuration
if [ -z "$CONFIG_FILE" ]; then
  CONFIG_FILE="$(dirname "$0")/config.json"
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found: $CONFIG_FILE"
  exit 1
fi

# Parse APEX application IDs from config using jq
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed. Please install jq."
  exit 1
fi

# Check if Docker is available
if ! command -v docker &>/dev/null; then
  echo "Error: Docker is required but not installed or not in PATH. Please install Docker."
  exit 1
fi

# Parse application IDs into a space-separated string, then convert to array
APP_IDS_STR=$(jq -r '.apex.applications | join(" ")' "$CONFIG_FILE")

if [ -z "$APP_IDS_STR" ] || [ "$APP_IDS_STR" = "null" ]; then
  echo "Error: No application IDs found in configuration file"
  exit 1
fi

# Convert to array using compatible method
IFS=' ' read -ra APP_IDS <<<"$APP_IDS_STR"

echo "Application IDs to export: ${APP_IDS[*]}"

# Parse database object filter from config
OBJECT_FILTER=$(jq -r '.database.object_filter // ""' "$CONFIG_FILE")

# Build Liquibase filter parameter
LB_FILTER=""
if [ -n "$OBJECT_FILTER" ] && [ "$OBJECT_FILTER" != "null" ] && [ "$OBJECT_FILTER" != "" ]; then
  LB_FILTER="-filter \"$OBJECT_FILTER\""
  echo "Using database object filter: $OBJECT_FILTER"
else
  echo "No database object filter specified - exporting all objects"
fi

# Check string connection
echo "Checking string connection"
if [ -z "$STR_CONN" ]; then
  while
    echo -n "STR_CONN (required): "
    read STR_CONN
    [[ -z $STR_CONN ]]
  do true; done
fi

# Check work directory
echo "Checking work directory"
if [ -z "$WORK_DIR" ]; then
  WORK_DIR=$(pwd)
fi

echo "Using work directory: $WORK_DIR"

FOLDER=$(basename "$WORK_DIR")
echo "Using: '$FOLDER' as tmp folder name"

# Recreating tmp dir
if [ -d $TMPDIR/tmp/stage_${FOLDER} ]; then
  rm -rf $TMPDIR/tmp/stage_${FOLDER}
fi
mkdir -p $TMPDIR/tmp/stage_${FOLDER}

# Helper function to execute SQLcl commands in Docker
run_sqlcl_docker() {
  local sql_commands="$1"
  local temp_sql_script="$TMPDIR/tmp/stage_${FOLDER}/temp_sqlcl_$RANDOM.sql"

  # Write SQL commands to temporary script (allowing variable expansion)
  cat > "$temp_sql_script" <<SQLEOF
$sql_commands
exit
SQLEOF

  # Build DNS arguments from host's DNS configuration
  local dns_args=""
  local dns_found=()
  local vpn_dns=()
  local public_dns=()

  # Try systemd-resolved first (common with VPNs on Linux)
  # This extracts DNS servers from ALL interfaces, including VPN (tun0, etc.)
  if command -v resolvectl &>/dev/null; then
    local current_interface=""
    while IFS= read -r line; do
      # Track current interface (e.g., "Link 10 (tun0)")
      if [[ $line =~ ^Link\ [0-9]+\ \((.+)\)$ ]]; then
        current_interface="${BASH_REMATCH[1]}"
      fi

      if [[ $line =~ DNS\ Servers:\ (.+) ]]; then
        for dns in ${BASH_REMATCH[1]}; do
          # Extract only IP address (remove anything after # like #dns.quad9.net)
          dns_ip="${dns%%#*}"
          # Validate it's a valid IPv4 format
          if [[ $dns_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # Avoid duplicates
            if [[ ! " ${dns_found[@]} " =~ " ${dns_ip} " ]]; then
              dns_found+=("$dns_ip")
              # Prioritize VPN DNS (tun*, ppp*, wg*, vpn* interfaces) and private IP ranges
              if [[ $current_interface =~ ^(tun|ppp|wg|vpn) ]] || [[ $dns_ip =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
                vpn_dns+=("$dns_ip")
              else
                public_dns+=("$dns_ip")
              fi
            fi
          fi
        done
      fi
    done < <(resolvectl status 2>/dev/null || true)

    # Build DNS args with VPN DNS first, then public DNS
    for dns in "${vpn_dns[@]}"; do
      dns_args="$dns_args --dns $dns"
    done
    for dns in "${public_dns[@]}"; do
      dns_args="$dns_args --dns $dns"
    done
  fi

  # Fallback to /etc/resolv.conf if no DNS found yet
  if [ -z "$dns_args" ] && [ -f /etc/resolv.conf ]; then
    while IFS= read -r line; do
      if [[ $line =~ ^nameserver[[:space:]]+([^[:space:]]+) ]]; then
        dns_args="$dns_args --dns ${BASH_REMATCH[1]}"
      fi
    done < /etc/resolv.conf
  fi

  docker run --rm \
    $dns_args \
    -v "$TMPDIR/tmp/stage_${FOLDER}:/work" \
    --entrypoint /bin/sh \
    container-registry.oracle.com/database/sqlcl:latest \
    -c "cd /work && sql /nolog @$(basename "$temp_sql_script")"

  local exit_code=$?
  rm -f "$temp_sql_script"

  if [ $exit_code -ne 0 ]; then
    echo "Error: Docker command failed with exit code $exit_code"
    exit $exit_code
  fi

  return 0
}

# extracting objects
echo "Extracting objects from schema"

# Export each APEX application individually
for app_id in "${APP_IDS[@]}"; do
  echo "Exporting APEX application: $app_id"
  run_sqlcl_docker "connect $STR_CONN
apex export -applicationid $app_id -skipExportDate -expOriginalIds -expSupportingObjects Y -expType APPLICATION_SOURCE -split"
done

# Export database schema and ORDS
echo "Exporting database schema and ORDS"

# Generate Liquibase commands conditionally
if [ -n "$LB_FILTER" ]; then
  echo "Exporting database objects with filter"

  # Create temporary SQL script with filter to avoid heredoc expansion issues
  cat >"$TMPDIR/tmp/stage_${FOLDER}/lb_export.sql" <<EOL
connect $STR_CONN
set ddl storage off
set ddl partitioning off
set ddl segment_attributes off
set ddl tablespace off
set ddl emit_schema off
lb generate-schema -split $LB_FILTER
lb generate-ords-schema
exit
EOL

  # Build DNS arguments from host's DNS configuration
  dns_args=""
  dns_found=()
  vpn_dns=()
  public_dns=()

  # Try systemd-resolved first (common with VPNs on Linux)
  # This extracts DNS servers from ALL interfaces, including VPN (tun0, etc.)
  if command -v resolvectl &>/dev/null; then
    current_interface=""
    while IFS= read -r line; do
      # Track current interface (e.g., "Link 10 (tun0)")
      if [[ $line =~ ^Link\ [0-9]+\ \((.+)\)$ ]]; then
        current_interface="${BASH_REMATCH[1]}"
      fi

      if [[ $line =~ DNS\ Servers:\ (.+) ]]; then
        for dns in ${BASH_REMATCH[1]}; do
          # Extract only IP address (remove anything after # like #dns.quad9.net)
          dns_ip="${dns%%#*}"
          # Validate it's a valid IPv4 format
          if [[ $dns_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # Avoid duplicates
            if [[ ! " ${dns_found[@]} " =~ " ${dns_ip} " ]]; then
              dns_found+=("$dns_ip")
              # Prioritize VPN DNS (tun*, ppp*, wg*, vpn* interfaces) and private IP ranges
              if [[ $current_interface =~ ^(tun|ppp|wg|vpn) ]] || [[ $dns_ip =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
                vpn_dns+=("$dns_ip")
              else
                public_dns+=("$dns_ip")
              fi
            fi
          fi
        done
      fi
    done < <(resolvectl status 2>/dev/null || true)

    # Build DNS args with VPN DNS first, then public DNS
    for dns in "${vpn_dns[@]}"; do
      dns_args="$dns_args --dns $dns"
    done
    for dns in "${public_dns[@]}"; do
      dns_args="$dns_args --dns $dns"
    done
  fi

  # Fallback to /etc/resolv.conf if no DNS found yet
  if [ -z "$dns_args" ] && [ -f /etc/resolv.conf ]; then
    while IFS= read -r line; do
      if [[ $line =~ ^nameserver[[:space:]]+([^[:space:]]+) ]]; then
        dns_args="$dns_args --dns ${BASH_REMATCH[1]}"
      fi
    done < /etc/resolv.conf
  fi

  docker run --rm \
    $dns_args \
    -v "$TMPDIR/tmp/stage_${FOLDER}:/work" \
    --entrypoint /bin/sh \
    container-registry.oracle.com/database/sqlcl:latest \
    -c "cd /work && sql /nolog @lb_export.sql"

  local exit_code=$?
  rm -f "$TMPDIR/tmp/stage_${FOLDER}/lb_export.sql"

  if [ $exit_code -ne 0 ]; then
    echo "Error: Docker command failed during database schema export with exit code $exit_code"
    exit $exit_code
  fi
else
  echo "Exporting all database objects"
  run_sqlcl_docker "connect $STR_CONN
set ddl storage off
set ddl partitioning off
set ddl segment_attributes off
set ddl tablespace off
set ddl emit_schema off
lb generate-schema -split
lb generate-ords-schema"
fi

#Ensure directory exists
echo "Ensure directory exists"
mkdir -p $WORK_DIR/database $WORK_DIR/rest_interfaces $WORK_DIR/apex_apps

# Remove old files
echo "Removing old files"
rm -rf $WORK_DIR/apex_apps/*
rm -rf $WORK_DIR/rest_interfaces/*
rm -rf $WORK_DIR/database/*

# Move Function folder
echo "Move Function folder"
rsync --delete --recursive $TMPDIR/tmp/stage_${FOLDER}/function $WORK_DIR/database 2>/dev/null
rm -rf $TMPDIR/tmp/stage_${FOLDER}/function

# Move apps folders
echo "Move apps folders"
rsync --delete --recursive $TMPDIR/tmp/stage_${FOLDER}/f* $WORK_DIR/apex_apps 2>/dev/null
rm -rf $TMPDIR/tmp/stage_${FOLDER}/f*

# Move ORDS interfaces
echo "Move ORDS interfaces"
rsync --delete --recursive $TMPDIR/tmp/stage_${FOLDER}/ords* $WORK_DIR/rest_interfaces/ 2>/dev/null
rm -rf $TMPDIR/tmp/stage_${FOLDER}/ords*

# Move database
echo "Move database"
rsync --delete --recursive $TMPDIR/tmp/stage_${FOLDER}/* $WORK_DIR/database 2>/dev/null
rm -rf $TMPDIR/tmp/stage_${FOLDER}/*

echo ""
echo "###########################################"
echo "APEX Export to Git completed successfully!"
echo "###########################################"
