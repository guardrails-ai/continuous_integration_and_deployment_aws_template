locals {
    deployment_name = "gr-backend"   
}

variable "aws_region" {
  description = "AWS region to deploy the resources"
  type        = string
  default     = "us-east-2"
}

variable "backend_cpu" {
  description = "CPU units for the service"
  type        = number
  default     = 1*1024
}

variable "backend_memory" {
  description = "Memory units for the service"
  type        = number
  default     = 2*1024
}

variable "backend_server_port" {
    description = "Port on which the backend server listens"
    type        = number
    default     = 8000
}

variable "desired_count" {
    description = "Number of tasks to run"
    type        = number
    default     = 0
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Offering    = "Guardrails Backend"
      Vendor      = "Guardrails"
      Terraform   = "True"
    }
  }
}

################# Networking Resources

data "aws_availability_zones" "available" {}


resource "aws_vpc" "backend" {
  cidr_block            = "10.0.0.0/16"
  enable_dns_hostnames  = true

  tags = {
    Name = "${local.deployment_name}-vpc"
  }
}

resource "aws_subnet" "backend_public_subnets" {
  count = 3
  vpc_id = aws_vpc.backend.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.deployment_name}-public-subnet-${count.index}"
  }
}

resource "aws_eip" "backend" {
  count      = 2
  vpc        = true
  depends_on = [aws_internet_gateway.backend]
}

resource "aws_nat_gateway" "backend" {
  count         = 2
  subnet_id     = aws_subnet.backend_public_subnets[count.index].id
  allocation_id = aws_eip.backend[count.index].id
}

resource "aws_internet_gateway" "backend" {
  vpc_id = aws_vpc.backend.id

  tags = {
    Name = "${local.deployment_name}-igw"
  }
}

resource "aws_route_table" "backend_public_routes" {
  vpc_id = aws_vpc.backend.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.backend.id
  }
}

resource "aws_route_table_association" "backend_public_routes" {
  count          = length(aws_subnet.backend_public_subnets)
  subnet_id      = aws_subnet.backend_public_subnets[count.index].id
  route_table_id = aws_route_table.backend_public_routes.id
}

resource "aws_lb" "app_lb" {
  name                             = "${local.deployment_name}-nlb"
  load_balancer_type               = "network"
  internal                         = false
  subnets                          = aws_subnet.backend_public_subnets[*].id
  enable_cross_zone_load_balancing = false
}

resource "aws_lb_listener" "app_lb_listener" {
  load_balancer_arn = aws_lb.app_lb.arn

  protocol = "TCP"
  port     = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_lb.arn
  }
}

resource "aws_lb_target_group" "app_lb" {
  name        = "${local.deployment_name}-nlb-tg"
  protocol    = "TCP"
  port        = 80
  vpc_id      = aws_vpc.backend.id
  target_type = "ip"

  health_check {
    healthy_threshold   = "2"
    interval            = "30"
    protocol            = "HTTP"
    timeout             = "3"
    unhealthy_threshold = "3"
    path                = "/"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "backend" {
  name        = "${local.deployment_name}-firewall"
  description = "Guardrails backend firewall"
  vpc_id      = aws_vpc.backend.id

  ingress {
    description = "Guardrails API Access"
    from_port   = var.backend_server_port
    to_port     = var.backend_server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  revoke_rules_on_delete = true
}

################# Log Resources

resource "aws_cloudwatch_log_group" "backend_log_group" {
  name              = "${local.deployment_name}-log-group"
  retention_in_days = 30
}

################# Application Resources

resource "aws_ecr_repository" "backend_images" {
  name = "${local.deployment_name}-images"
}

resource "aws_ecs_cluster" "backend" {
  name = "${local.deployment_name}-ecs-cluster"

  configuration {
    execute_command_configuration {
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = false
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.backend_log_group.name
      }
    }
  }

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_ecs_task_definition" "backend" {
  family                = "${local.deployment_name}-backend-task-defn"
  execution_role_arn    = aws_iam_role.ecs_execution_role.arn
  task_role_arn         = aws_iam_role.ecs_task_role.arn
  network_mode          = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                   = var.backend_cpu
  memory                = var.backend_memory

  container_definitions = jsonencode([
    {
      name             = "${local.deployment_name}-task",
      image            = "${aws_ecr_repository.backend_images.repository_url}:latest",
      cpu              = var.backend_cpu,
      memory           = var.backend_memory,
      networkMode      = "awsvpc",

      portMappings     = [
        {
          containerPort = var.backend_server_port,
          hostPort      = var.backend_server_port,
          protocol      = "tcp"
        }
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options   = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend_log_group.name,
          "awslogs-region"        = var.aws_region,
          "awslogs-stream-prefix" = "backend"
        }
      },
      linuxParameters  = {
        initProcessEnabled = true
      },
      healthCheck      = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.backend_server_port}/ || exit 1"],
        interval    = 30,
        startPeriod = 30,
        timeout     = 10,
        retries     = 3
      },
      environment      = [
        {
          name  = "AWS_ACCOUNT_ID",
          value = data.aws_caller_identity.current.account_id
        },
        {
          name  = "HOST",
          value = "http://${aws_lb.app_lb.dns_name}"
        },
        {
          name  = "SELF_ENDPOINT",
          value = "http://${aws_lb.app_lb.dns_name}:${var.backend_server_port}"
        }
      ],
      essential        = true
    }
  ])
}


resource "aws_ecs_service" "backend" {
  name            = "${local.deployment_name}-ecs-service"
  cluster         = aws_ecs_cluster.backend.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  enable_execute_command = true
  wait_for_steady_state  = true

  network_configuration {
    security_groups  = [aws_security_group.backend.id]
    subnets          = aws_subnet.backend_public_subnets[*].id
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_lb.id
    container_name   = "${local.deployment_name}-task"
    container_port   = var.backend_server_port
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}

################# IAM Roles and Policies

resource "aws_iam_role" "ecs_execution_role" {
  name = "${local.deployment_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${local.deployment_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
}

output "ecr_repository_url" {
  value = aws_ecr_repository.backend_images.repository_url
}

output "backend_service_url" {
  value = aws_lb.app_lb.dns_name
}