#!/bin/bash

set -exuo pipefail
xmlstarlet sel -t -m //apn -o 'mkdir -p operator/' -v ./@mcc -o / -v ./@mnc -n apns-full-conf.xml |sort -Vu|xargs -I {} sh -c {}
