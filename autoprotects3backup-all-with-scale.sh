  
AWS_PROFILE=my-profile-name
TODAY=$(date +"%m-%d-%Y")

NFS_MOUNT=("/mnt/cohesity1" "/mnt/cohesity2" "/mnt/cohesity3" "/mnt/cohesity4")
BUCKETS=($(
	aws s3api list-buckets --query "Buckets[].Name" --profile=$AWS_PROFILE --output text
))

for BUCKET_NAME in "${BUCKETS[@]}"
do
  TARGET_NFS=${NFS_MOUNT[RANDOM%${#NFS_MOUNT[@]}]}
  echo "Creating job for ${BUCKET_NAME}...";
  echo "aws s3 sync s3://$BUCKET_NAME $TARGET_NFS/$BUCKET_NAME --profile=$AWS_PROFILE" >> /tmp/jobrun_$TODAY.sh
done

echo "Running job....";
. /tmp/jobrun_$TODAY.sh

echo "S3 backup done!"
