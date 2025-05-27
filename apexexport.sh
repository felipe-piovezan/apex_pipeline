#!/bin/bash
# APEX Export to Git
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

# Parse application IDs into a space-separated string, then convert to array
APP_IDS_STR=$(jq -r '.apex.applications | join(" ")' "$CONFIG_FILE")

if [ -z "$APP_IDS_STR" ] || [ "$APP_IDS_STR" = "null" ]; then
  echo "Error: No application IDs found in configuration file"
  exit 1
fi

# Convert to array using compatible method
IFS=' ' read -ra APP_IDS <<<"$APP_IDS_STR"

echo "Application IDs to export: ${APP_IDS[*]}"

# Parse database object filters from config
INCLUDE_OBJECTS_STR=$(jq -r '.database.object_filters.include_objects | join(",")' "$CONFIG_FILE")
EXCLUDE_OBJECTS_STR=$(jq -r '.database.object_filters.exclude_objects | join(",")' "$CONFIG_FILE")

# Build Liquibase filter parameters for SQLcl
LB_FILTER=""
LB_HAS_FILTERS=false

# SQLcl uses -filter parameter with include/exclude syntax
FILTER_PARTS=""

if [ -n "$INCLUDE_OBJECTS_STR" ] && [ "$INCLUDE_OBJECTS_STR" != "null" ] && [ "$INCLUDE_OBJECTS_STR" != "" ]; then
  FILTER_PARTS="$FILTER_PARTS include:$INCLUDE_OBJECTS_STR"
  LB_HAS_FILTERS=true
  echo "Including database objects: $INCLUDE_OBJECTS_STR"
fi

if [ -n "$EXCLUDE_OBJECTS_STR" ] && [ "$EXCLUDE_OBJECTS_STR" != "null" ] && [ "$EXCLUDE_OBJECTS_STR" != "" ]; then
  if [ -n "$FILTER_PARTS" ]; then
    FILTER_PARTS="$FILTER_PARTS exclude:$EXCLUDE_OBJECTS_STR"
  else
    FILTER_PARTS="exclude:$EXCLUDE_OBJECTS_STR"
  fi
  LB_HAS_FILTERS=true
  echo "Excluding database objects: $EXCLUDE_OBJECTS_STR"
fi

if [ "$LB_HAS_FILTERS" = true ]; then
  LB_FILTER="-filter $FILTER_PARTS"
  echo "Using Liquibase filter: $FILTER_PARTS"
else
  echo "No database object filters specified - exporting all objects"
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

# extracting objects
echo "Extracting objects from schema"

# Export each APEX application individually
for app_id in "${APP_IDS[@]}"; do
  echo "Exporting APEX application: $app_id"
  sql /nolog <<EOF
cd $TMPDIR/tmp/stage_${FOLDER}
connect $STR_CONN
apex export -applicationid $app_id -skipExportDate -expOriginalIds -expSupportingObjects Y -expType APPLICATION_SOURCE -split
EOF
done

# Export database schema and ORDS
echo "Exporting database schema and ORDS"

# Generate Liquibase commands
echo "Exporting all database objects (filtering not supported in this SQLcl version)"
if [ "$LB_HAS_FILTERS" = true ]; then
  echo "Note: Object filters specified in config but SQLcl -filter syntax needs verification"
  echo "Filters: $FILTER_PARTS"
fi

sql /nolog <<EOF
cd $TMPDIR/tmp/stage_${FOLDER}
connect $STR_CONN
set ddl storage off
set ddl partitioning off
set ddl segment_attributes off
set ddl tablespace off
set ddl emit_schema off
lb generate-schema -split
lb generate-ords-schema
EOF

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
