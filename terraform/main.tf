terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "bg-vpc" }
}

# Public Subnets
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = { Name = "bg-public-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true
  tags = { Name = "bg-public-2" }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "bg-igw" }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "bg-rt" }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Security Group - ALB
resource "aws_security_group" "alb" {
  name   = "bg-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "bg-alb-sg" }
}

# Security Group - EC2
resource "aws_security_group" "ec2" {
  name   = "bg-ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "bg-ec2-sg" }
}

# ECR Repository
resource "aws_ecr_repository" "main" {
  name                 = "aws-blue-green-deployment"
  image_tag_mutability = "MUTABLE"
  tags = { Name = "aws-blue-green-deployment" }
}

# IAM Role for EC2
resource "aws_iam_role" "ec2" {
  name = "bg-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "bg-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ALB
resource "aws_lb" "main" {
  name               = "bg-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  tags = { Name = "bg-alb" }
}

# Blue Target Group
resource "aws_lb_target_group" "blue" {
  name     = "bg-blue-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/actuator/health"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }
  tags = { Name = "bg-blue-tg" }
}

# Green Target Group
resource "aws_lb_target_group" "green" {
  name     = "bg-green-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/actuator/health"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }
  tags = { Name = "bg-green-tg" }
}

# ALB Listener - points to Blue by default
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

# Blue EC2 Instance
resource "aws_instance" "blue" {
  ami                    = "ami-040e95ba14632401d"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  key_name               = "lup21"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io awscli
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu

    aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin ${aws_ecr_repository.main.repository_url}
    docker pull ${aws_ecr_repository.main.repository_url}:blue
    docker run -d -p 8080:8080 -e ENVIRONMENT=blue --restart always ${aws_ecr_repository.main.repository_url}:blue
  EOF
  )

  tags = { Name = "bg-blue-ec2" }
}

# Green EC2 Instance
resource "aws_instance" "green" {
  ami                    = "ami-040e95ba14632401d"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_2.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  key_name               = "lup21"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io awscli
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu

    aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin ${aws_ecr_repository.main.repository_url}
    docker pull ${aws_ecr_repository.main.repository_url}:green
    docker run -d -p 8080:8080 -e ENVIRONMENT=green --restart always ${aws_ecr_repository.main.repository_url}:green
  EOF
  )

  tags = { Name = "bg-green-ec2" }
}

# Attach Blue EC2 to Blue Target Group
resource "aws_lb_target_group_attachment" "blue" {
  target_group_arn = aws_lb_target_group.blue.arn
  target_id        = aws_instance.blue.id
  port             = 8080
}

# Attach Green EC2 to Green Target Group
resource "aws_lb_target_group_attachment" "green" {
  target_group_arn = aws_lb_target_group.green.arn
  target_id        = aws_instance.green.id
  port             = 8080
}

# Outputs
output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "ALB DNS - hit this to access your app"
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.main.repository_url
  description = "ECR URL"
}

output "blue_instance_id" {
  value       = aws_instance.blue.id
  description = "Blue EC2 Instance ID"
}

output "green_instance_id" {
  value       = aws_instance.green.id
  description = "Green EC2 Instance ID"
}