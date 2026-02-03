# A Cloud Project: CoolCatClub
This project showcases a website that I created years ago during my uni years. I brought it up again because I wanted to practice on building a production-grade infrastructure using Docker and Kubernetes in AWS EC2 through Terraform. I also built a basic CICD pipeline so whenever I make changes to the website code, it automatically deploys it to the live website. 

*_The website is just a basic test HTML/CSS for me to practice Terraform, Kubectl, AWS, and Github Actions. All cat art in the website are done by me._  

🛠 Tech Stack
- Infrastructure: Terraform (AWS EKS, VPC, ECR)
- Orchestration: Kubernetes (Deployments, Services, HPA)
- Containerization: Docker
- CI/CD: GitHub Actions
- Cloud: AWS

## Project Workflow
This section will show the step-by-steps on how to operate this deployment. 

### Deploying
**1. Initializing and building the infrastructure:**

For this step, make sure to be in the `coolcatclub` directory in the terminal.

```
cd terraform
terraform init
terraform apply
```

_This step will run the terraform files and build the infrastructure in AWS. It will take around 5-10 mins._

**2. Configure Kubernetes Access**

When the process for `terraform apply` is completed, we would need to configure the Kubernetes access in the terminal.

```
aws eks update-kubeconfig --region ap-southeast-1 --name coolcatclub-cluster
```

**3. Deploying the .yaml files**

Once the kubeconfig is applied, we can start applying the `.yaml` files with `kubectl`. Be sure to navigate to the k8s/ folder.

```
# Current path is .../coolcatclub
cd k8s
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f hpa.yaml
```

To access the web:
```
kubectl get svc coolcatclub-service
```

### Cleaning up
This is to avoid charges in AWS. 
```
# Delete K8s resources (to clean up the Load Balancer)
kubectl delete -f k8s/

# Destroy the infrastructure
cd terraform
terraform destroy -auto-approve

# Force-delete the ECR repo (if images remain)
aws ecr delete-repository --repository-name coolcatclub-web --force --region ap-southeast-1
```

## Building AWS Infrastructure with Terraform (IaC) ☁️
I started off this the project with building the Cloud architecture with Terraform (website and AWS account was already set up). For this website use case, I started with a monolithic architecture where the terraform file was provisioning a single EC2 host. The single `main.tf` file built the networking foundations _(VPC, subnet, internet gateway, route table, security group, and Elastic IP)_, the ECR repository for storing docker images, IAM role & instance profile, and the EC2 instance to build the docker image, push it to ECR, and run the container locally on port 80. 

<img width="1023" height="579" alt="Monolithic" src="https://github.com/user-attachments/assets/61ea6821-138f-4521-9bfe-5c5cb1ae4896" />

After this was built, I added a new `EKS.tf` file which created the EKS clusters. The reason for this was so that I could practice Kubernetes and know more about high availability, pod scheduling, and automated recovery. _I admit that this use case was a bit of an overkill since it's only hosting a single basic static website._ 

<img width="1023" height="579" alt="EKS Cluster" src="https://github.com/user-attachments/assets/aefa6a1b-881f-4660-8889-28133c5c6227" />

The `backend.tf` was created to store the `.tfstate` file into the S3 bucket. 

## The CICD Pipeline with GitHub Actions
This basic CICD pipeline was built using GitHub actions. The image below shows the workflow of the pipeline when the action for "push" is triggered on the main branch: 

<img width="599" height="1082" alt="CICD" src="https://github.com/user-attachments/assets/866db29b-6a32-47c1-ad6b-4552fc2e61fb" />

### Detailed Explanation:
#### 1. Trigger
The workflow starts when:
- Code is pushed to the `main` branch
- Manually triggered via GitHub Actions UI (`workflow_dispatch`)

#### 2. Authentication & Setup
- **Checkout Code**: Fetches your latest code from GitHub
- **AWS Credentials**: Uses GitHub Secrets to authenticate with AWS
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
- **Install Tools**: Sets up `kubectl` for Kubernetes commands

#### 3. Build Phase
```
GitHub Repository
       │
       ▼
Build Docker Image (from /website directory)
       │
       ▼
Tag with commit SHA (e.g., abc123def)
Tag with 'latest'
       │
       ▼
Push to Amazon ECR
       │
       ▼
ECR Repository: coolcatclub-web
```

**Why two tags?**
- **Commit SHA tag** (`abc123`): Specific version for rollbacks
- **`latest` tag**: Always points to newest version

#### 4. Deploy Phase**
```
ECR Image
    │
    ▼
kubectl connects to EKS cluster
    │
    ▼
Update deployment with new image
    │
    ▼
Kubernetes performs rolling update:
  • Starts new pods with new image
  • Waits for pods to be healthy
  • Terminates old pods
    │
    ▼
Deployment complete ✅
```

**Rolling Update Process**:
1. New pods spin up with updated image
2. Old pods continue serving traffic
3. Once new pods are healthy, traffic shifts
4. Old pods are terminated
5. Zero downtime!

#### 5. Verification
The workflow checks:
- **Pods**: Are they running?
- **HPA** (Horizontal Pod Autoscaler): Is autoscaling configured?
- **Service**: Is the LoadBalancer accessible?

#### 6. Smoke Test**
```
Get LoadBalancer URL → Wait for DNS → curl test → ✅ or ❌
```

#### 7. Rollback (if failure)
If anything fails:
```
❌ Deployment Failed
    │
    ▼
kubectl rollout undo
    │
    ▼
Reverts to previous working version
    │
    ▼
Disaster averted
```


