variable "aws_region" {
  default = "eu-west-3"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_key_pair" "demo_key" {
  key_name   = "MyKeyPair"
  public_key = file("~/.ssh/MyKeyPair.pub")
}

variable "public_key" {
  default = "~/.ssh/MyKeyPair.pub"
}

variable "private_key" {
  default = "~/.ssh/MyKeyPair.pem"
}

variable "number_of_instances" {
  description = "Number of instances to create and attach to ELB"
  default     = 2
}

resource "random_pet" "this" {
  length = 2
}

variable "ansible_user" {
  default = "ec2-user"
}

##################
# Creater the user 
##################
resource "aws_iam_user" "ecr_user" {
  name = "ecr_user"
}

resource "aws_iam_access_key" "ecr_user" {
  user = aws_iam_user.ecr_user.name
}

resource "aws_iam_user_policy" "ecr_user_ro" {
  name = "ecr_user_ro"
  user = aws_iam_user.ecr_user.name

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:*",
                "cloudtrail:LookupEvents"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateServiceLinkedRole"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "iam:AWSServiceName": [
                        "replication.ecr.amazonaws.com"
                    ]
                }
            }
        }
    ]
}
EOF

  provisioner "local-exec" {
    command = <<EOT
      rm ../playbooks/credentials && touch ../playbooks/credentials;
      echo "[default]" | tee -a ../playbooks/credentials;
      echo "aws_access_key_id = ${aws_iam_access_key.ecr_user.id}" | tee -a ../playbooks/credentials;
      echo "aws_secret_access_key = ${aws_iam_access_key.ecr_user.secret}" | tee -a ../playbooks/credentials;
      EOT
  }
}

#output "ecr_user_id" {
#  value = aws_iam_access_key.ecr_user.id
#}
#
#output "ecr_user_secret" {
#  value = aws_iam_access_key.ecr_user.secret
#}

###########################################################
# Create the ECR repository and push the docker image to it
###########################################################
resource "aws_ecr_repository" "docker_repo" {
  name                 = "iktos_test_app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  provisioner "local-exec" {
	command = <<EOT
    cd ../docker
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${self.repository_url}
    rm .env && touch .env;
    echo "DOCKER_REGISTRY=${self.repository_url}" | cut -f1 -d"/" | tee -a .env;
    docker-compose build --no-cache
    #docker tag docker_app:latest ${self.repository_url}:latest
    docker-compose push
    EOT
  }
}

output "ecr_repository_url" {
  value = aws_ecr_repository.docker_repo.repository_url
}


##############################################################
# Data sources to get VPC, subnets and security group details
##############################################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_security_group" "ssh" {
  name        = "default-ssh-example"
  description = "Security group for nat instances that allows SSH and VPN traffic from internet"

  ingress = [{
    "cidr_blocks": ["0.0.0.0/0"],
    "description": "HTTPS",
    "from_port": 22,
    "ipv6_cidr_blocks": null,
    "prefix_list_ids": null,
    "protocol": "tcp",
    "security_groups": null,
    "self": null,
    "to_port": 22
  }]

  tags = {
    Name = "ssh-example-default-vpc"
  }
}

resource "aws_security_group" "webservers" {
  name        = "allow_http"
  description = "Allow http inbound traffic"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

#########################
# S3 bucket for ELB logs
#########################
data "aws_elb_service_account" "this" {}

resource "aws_s3_bucket" "logs" {
  bucket        = "elb-logs-${random_pet.this.id}"
  acl           = "private"
  policy        = data.aws_iam_policy_document.logs.json
  force_destroy = true
}

data "aws_iam_policy_document" "logs" {
  statement {
    actions = [
      "s3:PutObject",
    ]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this.arn]
    }

    resources = [
      "arn:aws:s3:::elb-logs-${random_pet.this.id}/*",
    ]
  }
}

######
# ELB
######
resource "aws_elb" "terra-elb" {
  name               = "terra-elb"

  subnets         = data.aws_subnet_ids.all.ids
  security_groups = [
    aws_security_group.webservers.id,
    aws_security_group.ssh.id
  ]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  instances                   = module.ec2_instances.id
  cross_zone_load_balancing   = true
  idle_timeout                = 100
  connection_draining         = true
  connection_draining_timeout = 300

  tags = {
    Name = "terraform-elb"
  }

  access_logs {
    bucket = aws_s3_bucket.logs.id
  }

}

output "elb-dns-name" {
  value = aws_elb.terra-elb.dns_name
}

################
# EC2 instances
################
module "ec2_instances" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"

  instance_count = var.number_of_instances

  name                        = "my-app"
  ami                         = "ami-0ec28fc9814fce254"
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.demo_key.key_name
  subnet_id                   = element(tolist(data.aws_subnet_ids.all.ids), 0)
  associate_public_ip_address = true

  vpc_security_group_ids      = [
    aws_security_group.webservers.id,
    aws_security_group.ssh.id
  ]

  ebs_block_device = [{
    "device_name"           = "/dev/sdg"
    "volume_size"           = 500
    "volume_type"           = "io1"
    "iops"                  = 2000
    "encrypted"             = true
    "delete_on_termination" = true
  }]
}

resource "null_resource" "ec2_instances" {
  count  = var.number_of_instances

  # Changes to the instance will cause the null_resource to be re-executed
  triggers = {
    instance_ids = module.ec2_instances.id[count.index]
  }

  # Running the remote provisioner like this ensures that ssh is up and running
  # before running the local provisioner
  # Ansible requires Python to be installed on the remote machine as well as the local machine.
  # Add sudo yum update -y 
  provisioner "remote-exec" {
    inline = ["sudo yum install python3 -y"]
  }

  connection {
    type        = "ssh"
    private_key = file(var.private_key)
    user        = var.ansible_user
    host        = module.ec2_instances.public_ip[count.index]
  }

  # This is where we configure the instance with ansible-playbook
  provisioner "local-exec" {
	command = <<EOT
    sleep 30;
	  rm docker-${count.index}.ini && touch docker-${count.index}.ini;
	  echo "[docker]" | tee -a docker-${count.index}.ini;
	  echo "${module.ec2_instances.public_ip[count.index]} ansible_user=${var.ansible_user} ansible_ssh_private_key_file=${var.private_key}" | tee -a docker-${count.index}.ini;
    export ANSIBLE_HOST_KEY_CHECKING=False;
	  ansible-playbook -u ${var.ansible_user} --private-key ${var.private_key} -i docker-${count.index}.ini ../playbooks/ansible_playbook-aws-install-docker.yml --extra-vars "ecr_repository_url=${aws_ecr_repository.docker_repo.repository_url}"
    EOT
  }
}


output "ec2_ip" {
  value = module.ec2_instances.public_ip[*]
}