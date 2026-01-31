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

# ubuntu server & install apache2
resource "aws_instance" "web-server-instance" {
  ami               = "ami-08d59269edddde222"
  instance_type     = "t3.micro"
  availability_zone = "ap-southeast-1a"
  key_name          = "main-key"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo systemctl enable apache2
                sudo chown -R ubuntu:ubuntu /var/www/html
                # Create a flag file when setup is complete
                touch /tmp/cloud-init-complete
                EOF

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",  # Wait for cloud-init to complete
      "timeout 300 bash -c 'until [ -f /tmp/cloud-init-complete ]; do sleep 2; done'",  # Wait for our flag
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
    destination = "/home/ubuntu/website"  # More explicit destination
    
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/main-key.pem")
      host        = aws_eip.one.public_ip
    }
  }

    provisioner "remote-exec" {
        inline = [
        "echo 'Copying files to web root...'",
        "sudo cp -r /home/ubuntu/website/* /var/www/html/",
        "sudo chown -R www-data:www-data /var/www/html/",
        "sudo systemctl restart apache2",
        "echo 'Deployment complete!'"
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
