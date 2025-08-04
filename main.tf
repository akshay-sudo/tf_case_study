provider "aws" {
  region = "ap-south-1"
}

# 1. Create IAM User
resource "aws_iam_user" "web_restart_user" {
  name = "web-restart-user"
}

# 2. Create IAM Policy allowing SSM command to restart web servers
resource "aws_iam_policy" "restart_web_policy" {
  name        = "RestartWebServerPolicy"
  description = "Allows sending SSM commands to restart web servers"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "ssm:SendCommand",
        Resource = "*",
        Condition = {
          "StringEquals" = {
            "ssm:ResourceTag/Role" = "WebServer"
          },
          "StringLike" = {
            "ssm:DocumentName" = "AWS-RunShellScript"
          }
        }
      },
      {
        Effect = "Allow",
        Action = [
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ec2:DescribeInstances"
        ],
        Resource = "*"
      }
    ]
  })
}

# 3. Attach policy to user
resource "aws_iam_user_policy_attachment" "attach_restart_policy" {
  user       = aws_iam_user.web_restart_user.name
  policy_arn = aws_iam_policy.restart_web_policy.arn
}

# 4. Create IAM login credentials (access keys) – optional
resource "aws_iam_access_key" "web_restart_user_key" {
  user = aws_iam_user.web_restart_user.name
}


# 1. Create VPC (optional: use default if preferred)
resource "aws_vpc" "web_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "web_subnet_1" {
  vpc_id                  = aws_vpc.web_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "web_subnet_2" {
  vpc_id                  = aws_vpc.web_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.web_vpc.id
}

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.web_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta_1" {
  subnet_id      = aws_subnet.web_subnet_1.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_route_table_association" "rta_2" {
  subnet_id      = aws_subnet.web_subnet_2.id
  route_table_id = aws_route_table.route_table.id
}

# 2. Security Group
resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Allow HTTP"
  vpc_id      = aws_vpc.web_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. Launch Template
resource "aws_launch_template" "web_lt" {
  name_prefix   = "web-lt-"
  image_id      = "ami-0d0ad8bb301edb745"  # Amazon Linux 2 (update as needed)
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Web Server from ASG - $(hostname)</h1>" > /var/www/html/index.html
              EOF
  )
}

# 4. ALB + Target Group
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.web_subnet_1.id, aws_subnet.web_subnet_2.id]
}

resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.web_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "redirect"
    #target_group_arn = aws_lb_target_group.web_tg.arn
     
    redirect {
      port        = "8080"
      protocol    = "HTTP"
      status_code = "HTTP_301"
    }

  }
}

resource "aws_lb_listener" "http_8080_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}


# 5. Auto Scaling Group
resource "aws_autoscaling_group" "web_asg" {
  name                      = "web-asg"
  max_size                  = 3
  min_size                  = 1
  desired_capacity          = 2
  vpc_zone_identifier       = [aws_subnet.web_subnet_1.id, aws_subnet.web_subnet_2.id]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  target_group_arns         = [aws_lb_target_group.web_tg.arn]

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "WebASGInstance"
    propagate_at_launch = true
  }
}

