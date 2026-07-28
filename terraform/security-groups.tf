resource "aws_security_group" "alb_sg" {
  name   = "slack-style-alb-sg"
  vpc_id = aws_vpc.slack_style_vpc.id

  tags = {
    Name = "slack-style-alb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb_sg.id
  description       = "HTTP from anywhere"

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_all_out" {
  security_group_id = aws_security_group.alb_sg.id
  description       = "All outbound"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_security_group" "ecs_sg" {
  name   = "slack-style-ecs-sg"
  vpc_id = aws_vpc.slack_style_vpc.id

  tags = {
    Name = "slack-style-ecs-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id = aws_security_group.ecs_sg.id
  description       = "App port from ALB only"

  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port                    = 3000
  ip_protocol                  = "tcp"
  to_port                      = 3000
}

resource "aws_vpc_security_group_egress_rule" "ecs_all_out" {
  security_group_id = aws_security_group.ecs_sg.id
  description       = "All outbound"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_security_group" "redis_sg" {
  name   = "slack-style-redis-sg"
  vpc_id = aws_vpc.slack_style_vpc.id

  tags = {
    Name = "slack-style-redis-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_ecs" {
  security_group_id = aws_security_group.redis_sg.id
  description       = "Redis port from ECS only"

  referenced_security_group_id = aws_security_group.ecs_sg.id
  from_port                    = 6379
  ip_protocol                  = "tcp"
  to_port                      = 6379
}
