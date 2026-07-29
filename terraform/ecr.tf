resource "aws_ecr_repository" "web" {
  name = "ecr-repository-web"
}

resource "aws_ecr_repository" "worker" {
  name = "ecr-repository-worker"
}

resource "aws_ecs_cluster" "ecs_cluster_slack" {
  name = "slack-style-cluster"
}