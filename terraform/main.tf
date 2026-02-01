terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.30.0"
    }
  }
}

provider "aws" {
    region = "ap-southeast-1"
    profile = "default"
}

# vpc
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "production"
  }
}

# internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
}

# custom route table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prod"
  }
}

# subnet
resource "aws_subnet" "subnet-1" {
    vpc_id = aws_vpc.prod-vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "ap-southeast-1a"
    tags = {
      Name = "prod-subnet"
    }
}

# subnet -> route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# allow port 22,80,443
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

    ingress {
        description = "HTTPS"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        description = "HTTP"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        description = "SSH"
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
    Name = "Allow web"
  }
}

# network interface w/ ip subnet
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}

# elastic ip -> network interface
resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}

# ------------------------------------------------------------------------------->

# creating the ECR instance
resource "aws_ecr_repository" "website" {
  name                 = "coolcatclub-web"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "CoolCatClub-Website-Repo"
  }
}

# output ECR repo url
output "ecr_repo_url" {
  value       = aws_ecr_repository.website.repository_url
  description = "ECR repository URL"
}

# ------------------------------------------------------------------------------->
# IAM role that EC2 can assume
resource "aws_iam_role" "ec2_ecr_role" {
  name = "coolcatclub-ec2-ecr-role"

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

  tags = {
    Name = "CoolCatClub-EC2-Role"
  }
}

# Attach AWS managed policy for ECR access
resource "aws_iam_role_policy_attachment" "ecr_policy" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

# Create instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "coolcatclub-ec2-profile"
  role = aws_iam_role.ec2_ecr_role.name
}

# ------------------------------------------------------------------------------->

# ubuntu server with Docker
resource "aws_instance" "web-server-instance" {
  ami               = "ami-08d59269edddde222"
  instance_type     = "t3.micro"
  availability_zone = "ap-southeast-1a"
  key_name          = "main-key"
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                
                # Install Docker
                sudo apt install docker.io -y
                sudo systemctl start docker
                sudo systemctl enable docker
                sudo usermod -aG docker ubuntu

                # Install AWS CLI v2
                curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                sudo apt install unzip -y
                unzip awscliv2.zip
                sudo ./aws/install
                
                sudo chown -R ubuntu:ubuntu /home/ubuntu
                touch /tmp/cloud-init-complete
                EOF

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",  
      "timeout 300 bash -c 'until [ -f /tmp/cloud-init-complete ]; do sleep 2; done'",
    ]
    
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/main-key.pem")
      host        = aws_eip.one.public_ip
    }
  }

  provisioner "file" {
    source      = "../website"
    destination = "/home/ubuntu/website"
    
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/main-key.pem")
      host        = aws_eip.one.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Building Docker image...'",
      "cd /home/ubuntu/website",
      "sudo docker build -t coolcatclub-web:latest .",
      
      "echo 'Logging into ECR...'",
      "aws ecr get-login-password --region ap-southeast-1 | sudo docker login --username AWS --password-stdin ${aws_ecr_repository.website.repository_url}",
      
      "echo 'Tagging image for ECR...'",
      "sudo docker tag coolcatclub-web:latest ${aws_ecr_repository.website.repository_url}:latest",
      
      "echo 'Pushing to ECR...'",
      "sudo docker push ${aws_ecr_repository.website.repository_url}:latest",
      
      "echo 'Running container locally on port 80...'",
      "sudo docker run -d -p 80:80 --name web-server --restart unless-stopped ${aws_ecr_repository.website.repository_url}:latest",
      
      "echo 'Deployment complete! Image pushed to ECR and running locally.'"
    ]
    
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/main-key.pem")
      host        = aws_eip.one.public_ip
    }
  }

  tags = {
    Name = "CoolCatClub-Server"
  }
}

# output
output "server_public_ip" {
  value       = aws_eip.one.public_ip
  description = "The public IP address of the web server"
}