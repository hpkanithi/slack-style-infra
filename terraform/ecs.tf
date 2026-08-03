data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}

resource "aws_launch_template" "ecs_lt" {
  name_prefix   = "slack-style-ecs-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "t4g.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ecs_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster_slack.name}" >> /etc/ecs/ecs.config
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "slack-style-ecs-instance"
    }
  }
}

resource "aws_autoscaling_group" "ecs_asg" {
  name                = "slack-style-ecs-asg"
  min_size            = 3
  max_size            = 3
  desired_capacity    = 3
  vpc_zone_identifier = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]

  launch_template {
    id      = aws_launch_template.ecs_lt.id
    version = "$Latest"
  }

  protect_from_scale_in = true

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

resource "aws_ecs_capacity_provider" "cp" {
  name = "slack-style-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 1
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "cluster_cp" {
  cluster_name       = aws_ecs_cluster.ecs_cluster_slack.name
  capacity_providers = [aws_ecs_capacity_provider.cp.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.cp.name
    weight            = 100
  }
}

resource "aws_cloudwatch_log_group" "web_logs" {
  name              = "/ecs/slack-style-web"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "worker_logs" {
  name              = "/ecs/slack-style-worker"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "web" {
  family                   = "slack-style-web"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "256"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.web_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "web"
      image     = "${aws_ecr_repository.web.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "QUEUE_URL", value = aws_sqs_queue.queue.url },
        { name = "REDIS_ENDPOINT", value = aws_elasticache_cluster.redis_cluster.cache_nodes[0].address }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.web_logs.name
          "awslogs-region"        = "us-east-2"
          "awslogs-stream-prefix" = "web"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "slack-style-worker"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "256"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.worker_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = "${aws_ecr_repository.worker.repository_url}:latest"
      essential = true
      environment = [
        { name = "QUEUE_URL", value = aws_sqs_queue.queue.url },
        { name = "REDIS_ENDPOINT", value = aws_elasticache_cluster.redis_cluster.cache_nodes[0].address }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.worker_logs.name
          "awslogs-region"        = "us-east-2"
          "awslogs-stream-prefix" = "worker"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "web" {
  name            = "slack-style-web-svc"
  cluster         = aws_ecs_cluster.ecs_cluster_slack.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 2
  launch_type     = "EC2"

  network_configuration {
    subnets         = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web_tg.arn
    container_name   = "web"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.web_listener]
}

resource "aws_ecs_service" "worker" {
  name            = "slack-style-worker-svc"
  cluster         = aws_ecs_cluster.ecs_cluster_slack.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1
  launch_type     = "EC2"

  network_configuration {
    subnets         = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
    security_groups = [aws_security_group.ecs_sg.id]
  }
}