# Provider configuration
provider "aws" {
  region = "ap-south-1"
}

resource "aws_key_pair" "deployer" {
  key_name   = "id_rsa"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCvfliHljpN8wZoyXfMtOyyLhOIThcmZJrY7aOyliWZ/sGYZrTvZIQzW5FMDqjGlL//3TX/Nz9Av+dNgcgLElBJYMsJFqSNP7Sttq012PLk4GNNOm8nVto0ShVr1OmXEgTdXcqIVOUUaYmT3C+q+4oVzo4TmJdkx7awDJX/mV9zwElSYJi7SlhwOPSiflrLwhvzdT0Bw72bhbFLzxMNk3VZDZceN6cV41H6ogO4jsUcLfb5F58hN9vC4P7EEgRTX1iBM1IahizqK5ZLXCqEcFHMSnqMv17JUulEjbg0eYEViJcKV8A30ewcdT0g9RxCDsw7aSV2eq+UNmAh0wm36/h/ shadow@DESKTOP-SAGDLR0"
}
# VPC Creation
resource "aws_vpc" "three-tier-vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "three-tier-vpc"
  }
}

# Subnets Creation
resource "aws_subnet" "web_subnet" {
  vpc_id                  = aws_vpc.three-tier-vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "web-subnet"
  }
}

resource "aws_subnet" "app_subnet" {
  vpc_id                  = aws_vpc.three-tier-vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  tags = {
    Name = "app-subnet"
  }
}

resource "aws_subnet" "db_subnet" {
  vpc_id            = aws_vpc.three-tier-vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-south-1a"
  tags = {
    Name = "db-subnet"
  }
}

# Security Groups

# Web Tier Security Group
resource "aws_security_group" "three-tier-ec2-asg-sg" {
  name_prefix = "three-tier-web-sg-"
  description = "Allow HTTP traffic to web instances and allow traffic from app instances"
  vpc_id      = aws_vpc.three-tier-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24"]
    #security_groups = [aws_security_group.three-tier-app-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# App Tier Security Group
resource "aws_security_group" "three-tier-app-sg" {
  name_prefix = "three-tier-app-sg-"
  description = "Allow communication between web instances and DB instances"
  vpc_id      = aws_vpc.three-tier-vpc.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    security_groups = [aws_security_group.three-tier-ec2-asg-sg.id]
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
     cidr_blocks = ["10.0.3.0/24"]
   # security_groups = [aws_security_group.three-tier-db-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# DB Tier Security Group
resource "aws_security_group" "three-tier-db-sg" {
  name_prefix = "three-tier-db-sg-"
  description = "Allow MySQL traffic from app tier"
  vpc_id      = aws_vpc.three-tier-vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
     cidr_blocks = ["10.0.2.0/24"]
   # security_groups = [aws_security_group.three-tier-app-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB Security Group
resource "aws_security_group" "three-tier-alb-sg-1" {
  name_prefix = "three-tier-alb-sg-"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = aws_vpc.three-tier-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Internet Gateway
resource "aws_internet_gateway" "three-tier-igw" {
  vpc_id = aws_vpc.three-tier-vpc.id
  tags = {
    Name = "three-tier-igw"
  }
}

# Route Table and Association
resource "aws_route_table" "three-tier-rt" {
  vpc_id = aws_vpc.three-tier-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.three-tier-igw.id
  }

  tags = {
    Name = "three-tier-rt"
  }
}

resource "aws_route_table_association" "web_subnet_rt_association" {
  subnet_id      = aws_subnet.web_subnet.id
  route_table_id = aws_route_table.three-tier-rt.id
}

# ALB Creation
resource "aws_lb" "three-tier-alb" {
  name               = "three-tier-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups   = [aws_security_group.three-tier-alb-sg-1.id]
  subnets            = [aws_subnet.web_subnet.id]
  enable_deletion_protection = false

  enable_http2 = true

  tags = {
    Name = "three-tier-alb"
  }
}

# RDS Database Creation (MySQL)
resource "aws_db_instance" "three-tier-db" {
  identifier        = "three-tier-db"
  engine            = "mysql"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  db_name           = "threeTierDB"
  username          = "admin"
  password          = "12345"
  db_subnet_group_name = aws_db_subnet_group.three-tier-db-subnet-group.id
  vpc_security_group_ids = [aws_security_group.three-tier-db-sg.id]
  multi_az          = false
  publicly_accessible = false
  storage_encrypted = true

  tags = {
    Name = "three-tier-db"
  }
}

# DB Subnet Group for RDS
resource "aws_db_subnet_group" "three-tier-db-subnet-group" {
  name       = "three-tier-db-subnet-group"
  subnet_ids = [aws_subnet.db_subnet.id]
  tags = {
    Name = "three-tier-db-subnet-group"
  }
}

# EC2 Auto Scaling Group for Web Tier
resource "aws_launch_configuration" "web_launch_configuration" {
  name          = "web-launch-configuration"
  image_id      = "ami-0c55b159cbfafe1f0" # Use the appropriate AMI ID for your region
  instance_type = "t2.micro"
  key_name      = "id_rsa"
  security_groups = [aws_security_group.three-tier-ec2-asg-sg.id]
  user_data                   = <<-EOF
                                #!/bin/bash

                                # Update the system
                                sudo yum -y update

                                # Install Apache web server
                                sudo yum -y install httpd

                                # Start Apache web server
                                sudo systemctl start httpd.service

                                # Enable Apache to start at boot
                                sudo systemctl enable httpd.service

                                # Create index.html file with your custom HTML
                                sudo echo '<h1>Welcome! An Apache web server has been started successfully.</h1>' > /var/www/html/index.html
                                EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web_asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.web_subnet.id]
  launch_configuration = aws_launch_configuration.web_launch_configuration.id

  health_check_type       = "EC2"
  health_check_grace_period = 30

  tag {
    key                 = "Name"
    value               = "web-instance"
    propagate_at_launch = true
  }
}

# EC2 Auto Scaling Group for App Tier
resource "aws_launch_configuration" "app_launch_configuration" {
  name          = "app-launch-configuration"
  image_id      = "ami-0614680123427b75e" # Use the appropriate AMI ID for your region
  instance_type = "t2.micro"
  key_name      = "id_rsa"
  security_groups = [aws_security_group.three-tier-app-sg.id]
user_data = <<-EOF
                                #!/bin/bash

                                sudo yum install mysql -y

                                EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app_asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.app_subnet.id]
  launch_configuration = aws_launch_configuration.app_launch_configuration.id

  health_check_type       = "EC2"
  health_check_grace_period = 30

  tag {
    key                 = "Name"
    value               = "app-instance"
    propagate_at_launch = true
  }
}

output "dns_name_link" {
    value = aws_lb.three-tier-alb.dns_name
  
}
