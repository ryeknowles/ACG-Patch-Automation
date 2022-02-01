#!/bin/bash
# List disk in current project and create a dated pre-patch snapshot
gcloud compute disks list --format='value(name,zone)'| while read DISK_NAME ZONE; do
  gcloud compute disks snapshot $DISK_NAME --snapshot-names prepatch-${DISK_NAME:0:31}-$(date "+%Y-%m-%d-%s") --zone $ZONE
done
#
# Clean up snapshots that are over 60 days old
# Deleting a snapshot merges the oldest into the subsequent snapshot, so deleting does not delete data
#
if [[ $(uname) == "Linux" ]]; then
  from_date=$(date -d "-60 days" "+%Y-%m-%d")
else
  from_date=$(date -v -60d "+%Y-%m-%d")
fi
gcloud compute snapshots list --filter="creationTimestamp<$from_date" --regexp "(prepatch.*)" --uri | while read SNAPSHOT_URI; do
   gcloud compute snapshots delete $SNAPSHOT_URI --quiet
done
#
#Execute patch jobs of all VMs in project
gcloud compute os-config patch-jobs execute --instance-filter-all --rollout-mode=zone-by-zone --rollout-disruption-budget=10
