#!/bin/bash
############
#
# Author: Jason Brown
# Version: 1.0
# Purpose: Create or Destroy k8s cluster
#
#############

# 
# Set Global Varibales
#
DATE=`date +%F | sed s/-//g`
bucket_name=rocketfastsys-state-store-$DATE
cluster_decision=$1
export KOPS_CLUSTER_NAME=rocketfastsys.com
export KOPS_STATE_STORE=s3://${bucket_name}

do_check_creds ()
{
	#
	# Check if aws has been configured 
	#

	if [ ![ -s ~/.aws/credentials ] ]
	then
		echo "Please run: aws configure : commmand before running this script"
		exit 99
	fi
}

do_create_s3_bucket () 
{
	#
	# Create an S3 bucket with Versioning
	#

	aws s3api create-bucket --bucket ${bucket_name} --region us-east-1
	aws s3api put-bucket-versioning --bucket ${bucket_name} --versioning-configuration Status=Enabled

} #do_s3bucket

do_create_k8_cluster ()
{
	#
	# Create the k8s cluster
	#

	kops create cluster --name=rocketfastsys.com --dns-zone rocketfastsys.com --node-count=2 --node-size=t2.micro --master-size=t2.micro --zones=us-east-1a --name=${KOPS_CLUSTER_NAME} --zones=us-east-1a
	kops update cluster --name ${KOPS_CLUSTER_NAME}  --yes

	# Check if cluster has been validated 

	kops validate cluster
	badcluster=$?
	while [ $badcluster -gt 0 ]
        do
		kops validate cluster
		badcluster=$?
		if [ $badcluster -gt 0 ]
		then
			echo "Waiting 3 minutes before next check"
			sleep 250
		fi
	done

}

do_destroy_k8_cluster ()
{

	#
	# Destroy k8 cluster and S3 bucket
	#	
	
	kops delete cluster --name ${KOPS_CLUSTER_NAME} --yes
	versions=`aws s3api list-object-versions --bucket ${bucket_name} |jq '.Versions'`
	markers=`aws s3api list-object-versions --bucket ${bucket_name} |jq '.DeleteMarkers'`
	let count=`echo $versions |jq 'length'`-1
	
	if [ $count -gt -1 ]
	then
        	echo "removing files"
        	for i in $(seq 0 $count); do
                	key=`echo $versions | jq .[$i].Key |sed -e 's/\"//g'`
                	versionId=`echo $versions | jq .[$i].VersionId |sed -e 's/\"//g'`
                	cmd="aws s3api delete-object --bucket  ${bucket_name} --key $key --version-id $versionId"
                	echo $cmd
                	$cmd
        	done
	fi

	let count=`echo $markers |jq 'length'`-1

	if [ $count -gt -1 ]
	then
        	echo "removing delete markers"

        	for i in $(seq 0 $count)
		do
                	key=`echo $markers | jq .[$i].Key |sed -e 's/\"//g'`
                	versionId=`echo $markers | jq .[$i].VersionId |sed -e 's/\"//g'`
                	cmd="aws s3api delete-object --bucket  ${bucket_name} --key $key --version-id $versionId"
                	echo $cmd
                	$cmd
        	done
	fi

	aws s3api delete-bucket --bucket ${bucket_name}
}

#
# main
#

case $cluster_decision in
	C|c)
		do_check_creds
		do_create_s3_bucket
		do_create_k8_cluster
	;;
	D|d)
		do_check_creds
		do_destroy_k8_cluster
	;;
	*)
		echo "Please enter either c or C to Create a k8 cluster OR D or d to destroy a cluster"
esac
	
