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
