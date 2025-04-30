#!/bin/bash
# APEX Export to Git
STR_CONN=$1
WORK_DIR=$2

FOLDER=$(basename "$WORK_DIR")

# Recreating tmp dir
if [ -d $TMPDIR/tmp/stage_${FOLDER} ]
then
rm -rf $TMPDIR/tmp/stage_${FOLDER}
fi
mkdir -p $TMPDIR/tmp/stage_${FOLDER}


echo "$JAVA_HOME"
# extracting objects
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
mkdir -p $WORK_DIR $WORK_DIR/database

# Move workspace file
rsync --delete --recursive $TMPDIR/tmp/stage_${FOLDER}/w*.sql $WORK_DIR/apex_workspace/ 2>/dev/null
rm -rf $TMPDIR/tmp/stage_${FOLDER}/w*.sql

# Move Function folder
rsync --delete --recursive $TMPDIR/tmp/stage_${FOLDER}/function $WORK_DIR/database 2>/dev/null
rm -rf $TMPDIR/tmp/stage_${FOLDER}/function

# Move apps folders
rsync --delete --recursive $TMPDIR/tmp/stage_${FOLDER}/f* $WORK_DIR/apex_apps 2>/dev/null
rm -rf $TMPDIR/tmp/stage_${FOLDER}/f*

# Move ORDS interfaces
rsync --delete --recursive $TMPDIR/tmp/stage_${FOLDER}/ords* $WORK_DIR/rest_interfaces/ 2>/dev/null
rm -rf $TMPDIR/tmp/stage_${FOLDER}/ords*

# Move database
rsync --delete --recursive $TMPDIR/tmp/stage_${FOLDER}/* $WORK_DIR/database 2>/dev/null
rm -rf $TMPDIR/tmp/stage_${FOLDER}/*