data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "slack_style_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "slack-style-vpc"
  }
}

resource "aws_internet_gateway" "slack_style_igw" {
  vpc_id = aws_vpc.slack_style_vpc.id

  tags = {
    Name = "slack-style-igw"
  }
}

resource "aws_subnet" "pub_subnet_a" {
  vpc_id                  = aws_vpc.slack_style_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "slack-style-public-a"
  }
}

resource "aws_subnet" "pub_subnet_b" {
  vpc_id                  = aws_vpc.slack_style_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "slack-style-public-b"
  }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.slack_style_vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "slack-style-private-a"
  }
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.slack_style_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "slack-style-private-b"
  }
}


resource "aws_route_table" "route_pub" {
  vpc_id = aws_vpc.slack_style_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.slack_style_igw.id
  }

  tags = {
    Name = "slack-style-public-rt"
  }
}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.pub_subnet_a.id
  route_table_id = aws_route_table.route_pub.id
}

resource "aws_route_table_association" "pub_b" {
  subnet_id      = aws_subnet.pub_subnet_b.id
  route_table_id = aws_route_table.route_pub.id
}