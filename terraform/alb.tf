resource "aws_lb" "web_alb" {
  name               = "slack-style-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.pub_subnet_a.id, aws_subnet.pub_subnet_b.id]

  tags = {
    Name = "slack-style-alb"
  }
}

resource "aws_lb_target_group" "web_tg" {
  name        = "slack-style-web-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.slack_style_vpc.id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = {
    Name = "slack-style-web-tg"
  }
}

resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}