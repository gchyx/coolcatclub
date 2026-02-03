# A Cloud Project: CoolCatClub
---
This project showcases a website that I created years ago during my uni years. I brought it up again because I wanted to practice on building a production-grade infrastructure using Docker and Kubernetes in AWS EC2 through Terraform. I also built a basic CICD pipeline so whenever I make changes to the website code, it automatically deploys it to the live website. 

*_The website is just a basic test HTML/CSS for me to practice Terraform, Kubectl, AWS, and Github Actions. All cat art in the website are done by me._  

🛠 Tech Stack
- Infrastructure: Terraform (AWS EKS, VPC, ECR)
- Orchestration: Kubernetes (Deployments, Services, HPA)
- Containerization: Docker
- CI/CD: GitHub Actions
- Cloud: AWS

## Building the Cloud with Terraform (IaC)
---
I started off this the project with building the Cloud architecture with Terraform (website and AWS account was already set up). For this website use case, I started with a monolithic architecture where the terraform file was provisioning a single EC2 host. The single `main.tf` file built the networking foundations _(VPC, subnet, internet gateway, route table, security group, and Elastic IP)_, the ECR repository for storing docker images, IAM role & instance profile, and the EC2 instance to build the docker image, pushes it to ECR, and run the container locally on port 80. 

<img width="1023" height="579" alt="Monolithic" src="https://github.com/user-attachments/assets/61ea6821-138f-4521-9bfe-5c5cb1ae4896" />


After this was built, I added a new `EKS.tf` file which created the EKS clusters. The reason for this was so that I could practice Kubernetes and know more about high availability, pod scheduling, and automated recovery. _I admit that this use case was a bit of an overkill since it's only hosting a single basic static website._ 

<img width="1023" height="579" alt="EKS Cluster" src="https://github.com/user-attachments/assets/aefa6a1b-881f-4660-8889-28133c5c6227" />


The `backend.tf` was created to store the `.tfstate` file into the S3 bucket. 


## The CICD Pipeline
---
