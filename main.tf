####################################
# Terraform Provider Configuration
####################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # or whichever version you prefer
    }
  }
  required_version = ">= 1.6.0"
}

provider "aws" {
  region = var.aws_region
}
####################################
# Variables
####################################
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "instance_type" {
  type    = string
  default = "c7i-flex.large"
}

variable "key_name" {
  description = "Name of existing EC2 Key Pair in AWS"
  type        = string
  default     = "Devops-1"
}

variable "ubuntu_ami" {
  description = "Ubuntu AMI"
  type        = string
  default     = "ami-087d1c9a513324697"
}

####################################
# VPC
####################################
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "project-vpc"
  }
}

####################################
# Subnet
####################################
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

####################################
# Internet Gateway
####################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "project-igw"
  }
}

####################################
# Route Table
####################################
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

####################################
# Security Group
####################################
resource "aws_security_group" "main_sg" {
  name   = "project-sg"
  vpc_id = aws_vpc.main_vpc.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Puppet Server
  ingress {
    from_port   = 8140
    to_port     = 8140
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # can restrict to your web server
  }

  # Nagios NRPE
  ingress {
    from_port   = 5666
    to_port     = 5666
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "project-sg"
  }
}

####################################
# Web Server
####################################
resource "aws_instance" "web" {
  ami                    = var.ubuntu_ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.main_sg.id]
  key_name               = var.key_name

  # Install Nginx + Puppet Agent
  user_data = <<EOF
#!/bin/bash
apt update -y
apt install -y nginx wget

systemctl enable nginx
systemctl start nginx

# Install Puppet Agent
wget https://apt.puppet.com/puppet7-release-focal.deb
dpkg -i puppet7-release-focal.deb
apt update -y
apt install -y puppet-agent

# Configure Puppet Agent
mkdir -p /etc/puppetlabs/puppet
cat <<EOT >> /etc/puppetlabs/puppet/puppet.conf
[main]
server = ${aws_instance.puppet.private_ip}
EOT

# Run Puppet Agent once to request certificate
/opt/puppetlabs/bin/puppet agent -t
EOF

  tags = {
    Name = "web-server"
  }
}


# Puppet Server
resource "aws_instance" "puppet" {
  ami                    = var.ubuntu_ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.main_sg.id]
  key_name               = var.key_name

  user_data = <<EOF
#!/bin/bash
apt update -y
apt install -y wget

# Install Puppet Server
wget https://apt.puppet.com/puppet7-release-focal.deb
dpkg -i puppet7-release-focal.deb
apt update -y
apt install -y puppetserver

# Start Puppet Server
systemctl enable puppetserver
systemctl start puppetserver

# Reduce JVM memory for smaller instance
sed -i 's/2g/512m/g' /etc/default/puppetserver
systemctl restart puppetserver
EOF

  tags = {
    Name = "puppet-server"
  }
}

# Nagios Server
resource "aws_instance" "nagios" {
  ami                    = var.ubuntu_ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.main_sg.id]
  key_name               = var.key_name

  user_data = <<EOF
#!/bin/bash
apt update -y
apt install -y apache2 php php-cli gcc make wget unzip

# Install Nagios Core
cd /tmp
wget https://github.com/NagiosEnterprises/nagioscore/releases/download/nagios-4.4.14/nagios-4.4.14.tar.gz
tar zxvf nagios-4.4.14.tar.gz
cd nagios-4.4.14

./configure
make all
make install-groups-users
usermod -aG nagios www-data

make install
make install-daemoninit
make install-commandmode
make install-config

systemctl enable nagios
systemctl start nagios
EOF

  tags = {
    Name = "nagios-server"
  }
}

####################################
# Outputs
####################################
output "web_server_ip" {
  value = aws_instance.web.public_ip
}

output "puppet_server_ip" {
  value = aws_instance.puppet.public_ip
}

output "nagios_server_ip" {
  value = aws_instance.nagios.public_ip
}
