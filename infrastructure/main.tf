provider "aws" {
  region     = "us-east-1"
  access_key = var.aws_access_key       
  secret_key = var.aws_secret_key
}

# VPC Configuration
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "main-igw"
  }
}

# Subnets
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "private-subnet"
  }
}

# NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "nat-eip"
  }
}

resource "aws_nat_gateway" "gateway" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet.id
  depends_on    = [aws_internet_gateway.gw]
  tags = {
    Name = "main-nat-gw"
  }
}

# Route Tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gateway.id
  }
  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# Security Groups
resource "aws_security_group" "ec2_instance_sg" {
  name        = "ec2-instance-sg"
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-instance-sg"
  }
}

resource "aws_security_group" "ecs_task_sg" {
  name        = "ecs-task-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main_vpc.id

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

  tags = {
    Name = "ecs-task-sg"
  }
}

# IAM Roles
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "ecs-task-execution-role"
  }
}

resource "aws_iam_role" "ecs_ec2_instance_role" {
  name = "ecs-ec2-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "ecs-ec2-instance-role"
  }
}

resource "aws_iam_instance_profile" "ecs_ec2_instance_profile" {
  name = "ecs-ec2-instance-profile"
  role = aws_iam_role.ecs_ec2_instance_role.name
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_instance_policy" {
  role       = aws_iam_role.ecs_ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy" "ecr_pull_policy" {
  name   = "ecr-pull-policy"
  role   = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowPull",
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ],
        Resource = "*"
      }
    ]
  })
}

# ECS Cluster and Capacity Provider
resource "aws_ecs_cluster" "app_cluster" {
  name = "app-cluster"
  tags = {
    Name = "app-cluster"
  }
}

data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}


# Launch Template for Free Tier EC2 instances
resource "aws_launch_template" "ecs_ec2_launch_template" {
  name_prefix   = "ecs-ec2-lt-"
  description   = "Launch template for ECS EC2 instances"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t2.micro"  
  key_name      = aws_key_pair.ecs_key.key_name  

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_ec2_instance_profile.name
  }

  network_interfaces {
  associate_public_ip_address = true 
  security_groups             = [aws_security_group.ec2_instance_sg.id]
  }

  user_data = base64encode(<<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.app_cluster.name} >> /etc/ecs/ecs.config
EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ECS-EC2-Instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group using Launch Template
resource "aws_autoscaling_group" "ecs_ec2_asg" {
  name                = "ecs-ec2-asg-free-tier"  
  min_size            = 1
  max_size            = 1  
  desired_capacity    = 1
  vpc_zone_identifier = [aws_subnet.public_subnet.id]  

  launch_template {
    id      = aws_launch_template.ecs_ec2_launch_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "ECS-EC2-Instance-Free-Tier"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }
}

resource "aws_key_pair" "ecs_key" {
  key_name   = "ecs-instance-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCTP1Jy2i9HaQZpjuVdMugH++LnELk6Ym2TRCIUudVSizjDevRl+Dzyj3FldiUABtR3yW8ZsCyU3/CPGmtoVnQgTy8mrgGEcXTFls+WTuvUdW0hdpKxI+nI41NNuZEjEz/QJkZxgdpvuW92Do7clv1q7BqDHrtHUy9qbMGoYSor4Y5zyNjZuc5RVpjFEhdlxJHQufUP6xvJI6smnMTRsQuuTtKHE++xBc7GDk3UweHG0VaBGaKdwXyS05tGf03GRtj5QbIqlHVBl3c4WowI8UxqgXOHIu9LC44aT/h+VVF33BSmZumKqLQxKf5m0mOUS61BKZxUkvcyJ7rSqpAP0hDn rsa-key-20250410"
}



resource "aws_ecs_capacity_provider" "ec2_provider" {
  name = "ec2-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_ec2_asg.arn
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app_task" {
  family       = "app-task"
  network_mode = "bridge"
  requires_compatibilities = ["EC2"]

  container_definitions = jsonencode([{
    name      = "app"
    image     = "891377126793.dkr.ecr.us-east-1.amazonaws.com/xi:latest"
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80
      protocol      = "tcp"
    }]
    memory    = 512
    cpu       = 256
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/app-task"
        "awslogs-region"        = "us-east-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = {
    Name = "app-task-definition"
  }
}

# ECS Service
resource "aws_ecs_service" "app_service" {
  name            = "app-service"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 1
  launch_type     = "EC2"

  depends_on = [aws_autoscaling_group.ecs_ec2_asg]

  tags = {
    Name = "app-service"
  }
}

# CloudWatch Logs
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/ecs/app-task"
  retention_in_days = 7
  tags = {
    Name = "app-logs"
  }
}

# ECR Repository
resource "aws_ecr_repository" "app_ecr_repo" {
  name = "app-repository"
  tags = {
    Name = "app-ecr-repo"
  }
}

data "aws_instances" "ecs_instances" {
  instance_tags = {
    "aws:autoscaling:groupName" = aws_autoscaling_group.ecs_ec2_asg.name
  }
  depends_on = [aws_autoscaling_group.ecs_ec2_asg]
}

output "ecs_instance_public_ips" {
  description = "Public IP addresses of ECS container instances"
  value       = data.aws_instances.ecs_instances.public_ips
}

output "ecs_instance_private_ips" {
  description = "Private IP addresses of ECS container instances"
  value       = data.aws_instances.ecs_instances.private_ips
}
resource "aws_eip" "temp_eip" {
  vpc = true
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = data.aws_instances.ecs_instances.ids[0]
  allocation_id = aws_eip.temp_eip.id
}

output "temporary_public_ip" {
  value = aws_eip.temp_eip.public_ip
}