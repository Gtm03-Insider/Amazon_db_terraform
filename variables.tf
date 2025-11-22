variable "region" {
  # Description: AWS region where resources will be created.
  # Example: "us-east-1"
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  # Description: EC2 instance type to use for the VM.
  # Choose based on expected workload; default is a general-purpose instance.
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

// Variables for dev/aws module

variable "region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "SSH key pair name (existing). If `public_key` is set Terraform will create a key pair with this name."
  type        = string
  default     = "sample-key"
}

variable "public_key" {
  description = "Optional SSH public key material to create an `aws_key_pair`. Leave empty to use an existing key pair."
  type        = string
  default     = ""
}

variable "sql_sa_password" {
  description = "SA password for SQL Server (sensitive). Use Secrets Manager or SSM for production."
  type        = string
  default     = "P@ssw0rd123!"
  sensitive   = true
}

variable "sql_adm_s_password" {
  description = "Password for SQL_ADM_S login (sensitive)."
  type        = string
  default     = "AdmS@123!"
  sensitive   = true
}

variable "sql_dev_r_password" {
  description = "Password for SQL_DEV_R login (sensitive)."
  type        = string
  default     = "DevR@123!"
  sensitive   = true
}

variable "sql_dev_w_password" {
  description = "Password for SQL_DEV_W login (sensitive)."
  type        = string
  default     = "DevW@123!"
  sensitive   = true
}

variable "bitbucket_repo_url" {
  description = "Bitbucket repo HTTPS URL to clone (prefer SSH deploy keys for private repos)."
  type        = string
  default     = "https://bitbucket.org/yourteam/yourrepo.git"
}

variable "bitbucket_user" {
  description = "Bitbucket username for HTTPS cloning (not recommended for production)."
  type        = string
  default     = "bb_user"
}

variable "bitbucket_app_password" {
  description = "Bitbucket app password (sensitive). Use Secrets Manager in production."
  type        = string
  default     = "bb_app_password"
  sensitive   = true
}

variable "ssh_cidr" {
  description = "CIDR allowed to access SSH; change to your IP for testing."
  type        = string
  default     = "0.0.0.0/0"
}
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name for the AWS key pair (existing or created by terraform if public_key is provided)"
  type        = string
  default     = "sample-key"
}

variable "public_key" {
  description = "Optional SSH public key material; if provided, Terraform will create an aws_key_pair"
  type        = string
  default     = ""
}

variable "sql_sa_password" {
  description = "SA password for SQL Server (must meet complexity requirements)"
  type        = string
  default     = "P@ssw0rd123!"
}

variable "sql_adm_s_password" {
  description = "Password for SQL_ADM_S login"
  type        = string
  default     = "AdmS@123!"
}

variable "sql_dev_r_password" {
  description = "Password for SQL_DEV_R login"
  type        = string
  default     = "DevR@123!"
}

variable "sql_dev_w_password" {
  description = "Password for SQL_DEV_W login"
  type        = string
  default     = "DevW@123!"
}

variable "bitbucket_repo_url" {
  description = "Bitbucket repo URL to clone (placeholder for private repo)"
  type        = string
  default     = "https://bitbucket.org/yourteam/yourrepo.git"
}

variable "bitbucket_user" {
  description = "Bitbucket username or app user for HTTPS clone"
  type        = string
  default     = "bb_user"
}

variable "bitbucket_app_password" {
  description = "Bitbucket app password (placeholder)"
  type        = string
  default     = "bb_app_password"
}
