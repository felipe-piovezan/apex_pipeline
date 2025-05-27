#!/bin/bash

# load parameters
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
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq."
  exit 1
fi

# Parse application IDs into a space-separated string, then convert to array
APP_IDS_STR=$(jq -r '.apex.applications | join(" ")' "$CONFIG_FILE")

if [ -z "$APP_IDS_STR" ] || [ "$APP_IDS_STR" = "null" ]; then
  echo "Error: No application IDs found in configuration file"
  exit 1
fi

# Convert to array using compatible method
IFS=' ' read -ra APP_IDS <<< "$APP_IDS_STR"

echo "Application IDs to deploy: ${APP_IDS[*]}"

USERNAME=$(echo "$STR_CONN" | cut -d'/' -f1)

echo "Using Username: $USERNAME"
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

# Install database
echo "Install database objects"

sql /nolog <<EOF
connect $STR_CONN
cd $WORK_DIR/database
set ddl storage off
set ddl partitioning off
set ddl segment_attributes off
set ddl tablespace off
set ddl emit_schema off
lb update -changelog-file controller.xml
EOF

# Install apps
echo "Install apps"
base_dir="$WORK_DIR/apex_apps"

for folder in "$base_dir"/f[0-9][0-9][0-9]/; do
  # Check if it's a directory
  if [ -d "$folder" ]; then
    # Extract the folder name (e.g., f101, f102, etc.)
    folder_name=$(basename "$folder")

    # Extract the number part (XXX) from the folder name (removing the 'f' prefix)
    folder_number="${folder_name:1}"

    # Check if this app ID is in our configuration
    if [[ " ${APP_IDS[*]} " =~ " ${folder_number} " ]]; then
      echo "Processing folder: $folder (number: $folder_number)"
    else
      echo "Skipping folder: $folder (number: $folder_number) - not in configuration"
      continue
    fi

    # Call the sqlcl command and use the extracted number
    # Example: sqlcl username/password@db @script_${folder_number}.sql
    sql /nolog <<EOF
    connect $STR_CONN
    declare
      l_workspace apex_workspaces.workspace%type := '${USERNAME}';
      l_app_id apex_applications.application_id%type := $folder_number;
      l_schema apex_workspace_schemas.schema%type := '${USERNAME}';
    begin
      apex_application_install.set_workspace(l_workspace);
      apex_application_install.set_application_id(l_app_id);
      apex_application_install.set_auto_install_sup_obj( p_auto_install_sup_obj => true );
    end;
    /

    @$folder/install.sql
EOF
    # Optionally, handle error cases
    if [ $? -ne 0 ]; then
      echo "Error running sqlcl in $folder" >&2
    fi
  else
    echo "Skipping non-directory: $folder"
  fi
done

# Install rest
echo "Install REST Source"

sql /nolog <<EOF
connect $STR_CONN
cd $WORK_DIR/rest_interfaces
lb update -changelog-file ords_rest_schema.xml
EOF

echo ""
echo "###########################################"
echo "APEX Deploy completed successfully!"
echo "###########################################"
