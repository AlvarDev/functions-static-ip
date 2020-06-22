I always recommend to go to the [documentation](https://cloud.google.com/functions/docs/networking/network-settings) at first place. However, sometimes there are some concepts that are not so clear for everyone. In this case, network concepts for developers.  

When we hear **Serverless** we forgot almost everything about DevOps, networking, memory and so on, just worry about the code and that's ok. 

But now we have a requirement: _the client API only accepts requests from a whitelisted IP._

This is the schema for a 'traditional' architecture:

![Traditional](https://dev-to-uploads.s3.amazonaws.com/i/024rw3uxam4d58g4q4nd.png)

Cloud Functions will resolve most of the architecture but as you can see, some resources from a 'traditional' architecture are still necessary to achieve our objetive and that's where I want to help.

![Serverless](https://dev-to-uploads.s3.amazonaws.com/i/ae05zbq8q1pmw8nlf18n.png)

***
**Create a Simple HTTP Function**

_main.py_
```python
# This function will return the IP address for egress
import requests
import json

def test_ip(request):
    result = requests.get("https://api.ipify.org?format=json")
    return json.dumps(result.json())
```
deploy
```shell 
gcloud functions deploy testIP \
	--runtime python37 \
	--entry-point test_ip \
	--trigger-http \
	--allow-unauthenticated
```
test
```shell 
curl https://us-central1-your-project.cloudfunctions.net/testIP
# {"ip": "35.203.245.150"} (ephemeral: changes any time)
```
***
**Networking**

So this is the part that some devs going crazy, we're going to use a [VPC (Virtual Private Cloud)](https://cloud.google.com/vpc) that provides networking functionalities to out cloud-based services, in this case our Cloud Function.

>_VPC networks do not have any IP address ranges associated with them. IP ranges are defined for the subnets._

```shell
# Create VPC
gcloud services enable compute.googleapis.com

gcloud compute networks create my-vpc \
    --subnet-mode=custom \
    --bgp-routing-mode=regional
```
  
Then we have to create a Serverless VPC Access connector that allows Cloud functions (an another Serverless resources) to connect with a VPC.

```shell
# Create a Serverless VPC Access connectors 
gcloud services enable vpcaccess.googleapis.com

gcloud compute networks vpc-access connectors create functions-connector \
	--network my-vpc \
	--region us-central1 \
	--range 10.8.0.0/28
```

Before we can use our _**functions-connector**_ we have to grant the appropriate permissions to the _Cloud Functions service account_, so the Cloud Functions will be able to connect to our _**functions-connector**_.

```shell
# Grant Permissions 
export PROJECT_ID=$(gcloud config list --format 'value(core.project)')
export PROJECT_NUMBER=$(gcloud projects list --filter="$PROJECT_ID" --format="value(PROJECT_NUMBER)")

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member=serviceAccount:service-$PROJECT_NUMBER@gcf-admin-robot.iam.gserviceaccount.com \
--role=roles/viewer

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member=serviceAccount:service-$PROJECT_NUMBER@gcf-admin-robot.iam.gserviceaccount.com \
--role=roles/compute.networkUser
```

Ok, we have the connector and the permissions, let's configure our Cloud Function to use the connector. 

```shell
# Configurate the connector
gcloud functions deploy testIP \
	--runtime python37 \
	--entry-point test_ip \
	--trigger-http \
	--allow-unauthenticated \
	--vpc-connector functions-connector \
	--egress-settings all
```

If you make a request to our Cloud Function you will see this message: _"Error: could not handle the request"_ that's because our **VPC** doesn't have any exit to the internet.

In order to be accessible to the outside world we have to:

* Reserve a [static IP](https://cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address#reserve_new_static). 

* Configure a [Cloud Router](https://cloud.google.com/network-connectivity/docs/router/concepts/overview) to route our network traffic.

* Create a [Cloud Nat] (https://cloud.google.com/nat) to allow our instances without external IP to send outbound packets to the internet and receive any corresponding established inbound response packets (aka via static IP).

```shell
# Reserve static IP
gcloud compute addresses create functions-static-ip \
    --region=us-central1

gcloud compute addresses list
# NAME                 ADDRESS/RANGE  TYPE      PURPOSE  NETWORK  REGION       SUBNET  STATUS
# functions-static-ip  34.72.171.164  EXTERNAL                    us-central1          RESERVED
```

We have our static IP! 34.72.171.164

```shell
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
```

Awesome! now let's try our Cloud Functions with a new request

```shell
curl https://us-central1-your-project.cloudfunctions.net/testIP
# {"ip": "34.72.171.164"} (our static IP!)
```

  

Yay! everything is working :) a little recap:

  
1. We have deployed a simple _Cloud Function (HTTP)_.

2. Created a _VPC_ to provide networking functionalities to our Cloud Function.

3. Created a _Serverless VPC Access connector_ to allow our Cloud Function to use VPC functionalities (like use IPs for example).

4. Granted permissions to the _Cloud Functions Service Account_ to use network resourcing.

5. Configured the _Cloud Function_ to use the _Serverless VPC Access connector_ and redirect all the outbound request through the _VPC_

6. Reserved a _static IP_.

7. Created a _Cloud Router_ to route our network traffic.

8. An finally create a _Cloud Nat_ to communicate with the outside world.
  


Hope this post helps you and let me know if you have any questions or recommendations.
