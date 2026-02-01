# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "coolcatclub-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Node IAM Role
resource "aws_iam_role" "eks_node_role" {
  name = "coolcatclub-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# another subnet for EKS
resource "aws_subnet" "subnet-2" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-southeast-1b"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "prod-subnet-2"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet-2.id
  route_table_id = aws_route_table.prod-route-table.id
}

# EKS Cluster
resource "aws_eks_cluster" "coolcatclub" {
  name     = "coolcatclub-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.subnet-1.id,
      aws_subnet.subnet-2.id
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = "CoolCatClub-EKS-Cluster"
  }
}

# EKS Node Group
resource "aws_eks_node_group" "coolcatclub" {
  cluster_name    = aws_eks_cluster.coolcatclub.name
  node_group_name = "coolcatclub-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [
    aws_subnet.subnet-1.id,
    aws_subnet.subnet-2.id
  ]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.small"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]

  tags = {
    Name = "CoolCatClub-EKS-Nodes"
  }
}

# Outputs
output "eks_cluster_endpoint" {
  value       = aws_eks_cluster.coolcatclub.endpoint
  description = "EKS cluster endpoint"
}

output "eks_cluster_name" {
  value       = aws_eks_cluster.coolcatclub.name
  description = "EKS cluster name"
}

# Install Metrics Server (for HPA)
resource "null_resource" "install_metrics_server" {
  depends_on = [aws_eks_node_group.coolcatclub]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ap-southeast-1 --name ${aws_eks_cluster.coolcatclub.name}
      kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    EOT
  }
}