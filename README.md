# Terraform Ansible AWS Docker ECR ELB
Python API and DB dockerised and deployed to AWS instances with an elastic load balancer using Terraform and Ansible.

## Current architecture
![Current architecture of the project generated using app.diagrams.net](docs/iktos-test-diagram.png?raw=true)

In the current architecture we use Terraform to provide two EC2 instances running Amazon Linux 2 with a docker container running a basic web API.
The two instances are run inside an elastic load balancer and the docker image is provided by the elastic container registry.

The web app uses Flask with Python and MySQL for the database and we make it run with Docker and docker-compose.

For best practice we want our container to have only one responsibility and one process, so for our app we use two.
One for running the app itself, and one for running the database.

By using infrastructure as code software we ensure the reproducibility, disposability and accessibility of the resources of the project.
Ansible allows us to automatically configure the created instances.
The docker image is pushed to the ECR during the apply.

## Project structure
```sh
├── docker
│   ├── app
│   │   ├── Dockerfile       # Docker file containing all the commands to assemble the image
│   │   ├── app.py           # Our python api
│   │   ├── requirements.txt # Python dependencies
│   │   └── test.http        # Test file to try requests when the container is running locally
│   ├── db
│   │   ├── data
│   │   │   └── adult.data   # Data for the DB
│   │   └── init.sql         # Initialization file for the DB
│   └── docker-compose.yml   # Docker compose file to configure all of the application's service dependencies
├── playbooks
│   ├── ansible_....yml      # Ansible file to configure the instances
│   └── config.json          # Config file for docker to connect to ECR inside the instances
└── terraform
    └── main.tf              # Main terraform file provisioning the infrastructure
```

## Next development step that would be nice to add
* Use a production ready web server
* Add continuous integration/delivery functionalities in a CI/CD fashion with jenkins or some alternative
* Add EC2 autoscaling
* Change the app database to use something more robust/distributed
* Store and sync the Terraform .tfstate to a backend and not locally

---

## How to deploy the application

### Prerequisites:

- [AWS CLI](https://aws.amazon.com/fr/cli/)
- [Terraform](https://www.terraform.io/downloads.html)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
- [Docker Desktop](https://www.docker.com/products/docker-desktop)

Make sure docker is running locally

### Defining SSH key-pair files

The SSH key-pair files defined here will be used in the Terraform to connect to the EC2 instances with this credential.
Intentionally, all components use the same certificate for ease of use.

```sh
$ ssh-keygen -t rsa -b 2048 -f ~/.ssh/MyKeyPair.pem -q -P ''
$ chmod 400 ~/.ssh/MyKeyPair.pem
$ ssh-keygen -y -f ~/.ssh/MyKeyPair.pem > ~/.ssh/MyKeyPair.pub
```

### Running the Terraform
Terraform will perform all the actions and call Ansible for the instances configuration

```sh
# Open the terraform directory
$ cd terraform

# Init terraform
$ terraform init

# See the current plan
$ terraform plan

# Apply the current plan
$ terraform apply

# See the output values, useful for testing individual resources
$ terraform output
```

### Checking the results
At apply you should be provided with the following results

The output from the Ansible test run by Terraform of the web API:
```sh
null_resource.ec2_instances[0] (local-exec): ok: [ip] => (item=/api/v1/first_row)
null_resource.ec2_instances[0] (local-exec): ok: [ip] => (item=/api/v1/mean_value?column_name=age)
null_resource.ec2_instances[0] (local-exec): ok: [ip] => (item=/api/v1/most_frequentvalue?column_name=age)
```

The output from Terraform:
```sh
Apply complete! Resources: 14 added, 0 changed, 0 destroyed.

Outputs:
ec2_ip = [ip1, ip2]
ecr_repository_url = <ecr_repository_url>
elb-dns-name = <elb-dns-name>
```
You can then connect to the outputted elb-dns-name to see if the app is running correctly


### Destroy all the created resources
To destroy the architecture you can run the following command
```diff
$ terraform destroy
```
---

## Running some tests

### Uploading the docker files to the container registry
```sh
# Open the docker directory
$ cd docker

#Get an authentication token and authenticate the Docker client with the registry.
$ aws ecr get-login-password --region eu-west-3 | docker login --username AWS --password-stdin <ecr_repository_url>

#Create the Docker environnement file
$ echo "DOCKER_REGISTRY=<ecr_repository_url>" | cut -f1 -d"/" | tee -a .env

#Create the docker image
$ docker-compose build 

#Push the image to the latest AWS repository
$ docker-compose push
```


### Test connecting to one instance
```sh
ssh -i ~/.ssh/MyKeyPair.pem ec2-user@<instance_ip>
```

### Test running the Ansible playbook directly on one instance
```sh
ansible-playbook -u ec2-user --private-key ~/.ssh/MyKeyPair.pem -i docker-0.ini ../playbooks/ansible_playbook-aws-install-docker.yml --extra-vars "ecr_repository_url=<ecr_repository_url>"
```