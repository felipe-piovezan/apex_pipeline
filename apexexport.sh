#!/bin/bash
# APEX Export to Git
STR_CONN=$1
WORK_DIR=$2

# Check string connection
echo "Checking string connection"
if [ -z "$STR_CONN" ]
then
    while
        echo -n "STR_CONN (required): "
        read STR_CONN
        [[ -z $STR_CONN ]]
    do true; done
fi

# Check work directory
echo "Checking work directory"
if [ -z "$WORK_DIR" ]
then
    WORK_DIR=$(pwd)
fi

echo "Using work directory: $WORK_DIR"

FOLDER=$(basename "$WORK_DIR")
echo "Using: '$FOLDER' as tmp folder name"

# Recreating tmp dir
if [ -d $TMPDIR/tmp/stage_${FOLDER} ]
then
rm -rf $TMPDIR/tmp/stage_${FOLDER}
fi
mkdir -p $TMPDIR/tmp/stage_${FOLDER}


# extracting objects
echo "Extracting objects from schema"
sql /nolog <<EOF
cd $TMPDIR/tmp/stage_${FOLDER}
connect $STR_CONN
apex export -instance -split -skipExportDate -expOriginalIds -expSupportingObjects Y -expType APPLICATION_SOURCE
apex export -instance -expworkspace -overwrite-files -skipexportdate
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
mkdir -p $WORK_DIR/database $WORK_DIR/rest_interfaces $WORK_DIR/apex_workspace $WORK_DIR/apex_apps

# Remove old files
echo "Removing old files"
rm -rf $WORK_DIR/apex_workspace/*
rm -rf $WORK_DIR/apex_apps/*
rm -rf $WORK_DIR/rest_interfaces/*
rm -rf $WORK_DIR/database/*

# Move workspace file
echo "Move workspace file"
rsync --delete --recursive $TMPDIR/tmp/stage_${FOLDER}/w*.sql $WORK_DIR/apex_workspace/ 2>/dev/null
rm -rf $TMPDIR/tmp/stage_${FOLDER}/w*.sql

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