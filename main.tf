provider "aws" {
  region = "us-west-1"
}

resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "eks-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  count = 2

  cidr_block = element(["10.0.1.0/24", "10.0.2.0/24"], count.index)
  vpc_id     = aws_vpc.eks_vpc.id

  availability_zone      = element(["us-west-1a", "us-west-1c"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnet" {
  count = 2

  cidr_block = element(["10.0.3.0/24", "10.0.4.0/24"], count.index)
  vpc_id     = aws_vpc.eks_vpc.id

  availability_zone = element(["us-west-1a", "us-west-1c"], count.index)

  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "eks-igw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count = 2

  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "eks_cluster_sg" {
  vpc_id = aws_vpc.eks_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-cluster-sg"
  }
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = "my-eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = aws_subnet.private_subnet[*].id
  }
}

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = ["eks.amazonaws.com", "ec2.amazonaws.com"],
        },
      },
    ],
  })
}

resource "aws_iam_policy" "eks_cluster_policy" {
  name        = "eks-cluster-policy"
  description = "Policy for EKS cluster role"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "eks:DescribeCluster",
        Effect   = "Allow",
        Resource = aws_eks_cluster.eks_cluster.arn,
      },
      {
        Action   = "eks:ListNodegroups",
        Effect   = "Allow",
        Resource = aws_eks_cluster.eks_cluster.arn,
      },
      {
        Action   = "eks:CreateNodegroup",
        Effect   = "Allow",
        Resource = aws_eks_cluster.eks_cluster.arn,
      },
      {
        Action   = "eks:TagResource",
        Effect   = "Allow",
        Resource = aws_eks_cluster.eks_cluster.arn,
      },
      {
        Action   = "ec2:CreateTags",
        Effect   = "Allow",
        Resource = "*",
      },
    ],
  })
  lifecycle {
    create_before_destroy = true
  }
}

variable "create_eks_attachment" {
  description = "Whether to create IAM role policy attachment for EKS cluster"
  type        = bool
  default     = true  # Adjust the default value based on your requirements
}

resource "aws_iam_role_policy_attachment" "eks_cluster_attachment" {
  count       = var.create_eks_attachment ? 1 : 0
  policy_arn  = aws_iam_policy.eks_cluster_policy.arn
  role        = aws_iam_role.eks_cluster.name
}

resource "aws_eks_node_group" "eks_nodes" {
  cluster_name   = aws_eks_cluster.eks_cluster.name
  node_group_name = "eks-nodes"

  node_role_arn = aws_iam_role.eks_cluster.arn

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  subnet_ids      = aws_subnet.private_subnet[*].id
  instance_types  = ["t2.small"]
}
