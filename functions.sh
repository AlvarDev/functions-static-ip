# Deploy HTTP Functions
gcloud functions deploy testIP \
	--runtime python37 \
	--entry-point test_ip \
	--trigger-http \
	--allow-unauthenticated

curl https://us-central1-your-project.cloudfunctions.net/testIP
# {"ip": "35.203.245.150"} (ephemeral: changes any time)


# Create VPC
gcloud services enable compute.googleapis.com

gcloud compute networks create my-vpc \
    --subnet-mode=custom \
    --bgp-routing-mode=regional


# Create a Serverless VPC Access connectors 
gcloud services enable vpcaccess.googleapis.com

gcloud compute networks vpc-access connectors create functions-connector \
	--network my-vpc \
	--region us-central1 \
	--range 10.8.0.0/28


# Grant Permissions 
export PROJECT_ID=$(gcloud config list --format 'value(core.project)')
export PROJECT_NUMBER=$(gcloud projects list --filter="$PROJECT_ID" --format="value(PROJECT_NUMBER)")

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member=serviceAccount:service-$PROJECT_NUMBER@gcf-admin-robot.iam.gserviceaccount.com \
--role=roles/viewer

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member=serviceAccount:service-$PROJECT_NUMBER@gcf-admin-robot.iam.gserviceaccount.com \
--role=roles/compute.networkUser


# Configurate the connector
gcloud functions deploy testIP \
	--runtime python37 \
	--entry-point test_ip \
	--trigger-http \
	--allow-unauthenticated \
	--vpc-connector functions-connector \
	--egress-settings all


# Reserve static IP
gcloud compute addresses create functions-static-ip \
    --region=us-central1

gcloud compute addresses list
# NAME                 ADDRESS/RANGE  TYPE      PURPOSE  NETWORK  REGION       SUBNET  STATUS
# functions-static-ip  34.72.171.164  EXTERNAL                    us-central1          RESERVED


# Creating the Cloud Router
gcloud compute routers create my-router \
    --network my-vpc \
    --region us-central1

# Creating Cloud Nat
gcloud compute routers nats create my-cloud-nat-config \
	--router=my-router \
    --nat-external-ip-pool=functions-static-ip \
    --nat-all-subnet-ip-ranges \
    --enable-logging

curl https://us-central1-your-project.cloudfunctions.net/testIP
# {"ip": "34.72.171.164"} (our static IP!)

    














	