// Provider: AWS
// Description: Configures the AWS provider and target region for resources.
provider "aws" {
  region = var.region
}

// Data source: Latest Ubuntu 22.04 AMI
// Description: Looks up the most recent Canonical Ubuntu 22.04 AMI to use
// for the EC2 instance. This ensures we use a maintained OS image.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

// Resource: aws_key_pair (optional)
// Description: Creates an AWS key pair with the provided public key so you
// can SSH into the instance. This resource is only created when
// `public_key` is provided; otherwise we expect an existing keypair named
// by `key_name`.
resource "aws_key_pair" "deployer" {
  count      = var.public_key == "" ? 0 : 1
  key_name   = var.key_name
  public_key = var.public_key
}

// Resource: aws_security_group
// Description: Security group allowing SSH access (port 22) and MSSQL
// traffic (port 1433). For production, restrict `cidr_blocks` to trusted
// networks only instead of 0.0.0.0/0.
resource "aws_security_group" "mssql_sg" {
  name        = "mssql-sg"
  description = "Allow SSH and MSSQL"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MSSQL"
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// Resource: aws_instance
// Description: Creates an EC2 instance running Ubuntu. The `user_data`
// passed here runs the `mssql_setup.sh.tpl` template to install SQL Server,
// create the requested databases, filegroups, users and run Bitbucket scripts.
resource "aws_instance" "mssql" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.mssql_sg.id]
  key_name               = var.key_name

  # Templated user-data will be rendered and executed on first boot.
  user_data = templatefile("${path.module}/mssql_setup.sh.tpl", {
    sa_password        = var.sql_sa_password
    adm_password       = var.sql_adm_s_password
    dev_r_password     = var.sql_dev_r_password
    dev_w_password     = var.sql_dev_w_password
    bitbucket_repo     = var.bitbucket_repo_url
    bitbucket_user     = var.bitbucket_user
    bitbucket_app_pass = var.bitbucket_app_password
  })

  tags = {
    Name = "mssql-terraform-test"
  }
}

// Output: Public IP of the EC2 instance
output "instance_public_ip" {
  value = aws_instance.mssql.public_ip
}
provider "aws" {
  region = var.region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "deployer" {
  count      = var.public_key == "" ? 0 : 1
  key_name   = var.key_name
  public_key = var.public_key
}

resource "aws_security_group" "mssql_sg" {
  name        = "mssql-sg"
  description = "Allow SSH and MSSQL"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MSSQL"
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "mssql" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.mssql_sg.id]
  key_name               = var.key_name

  user_data = templatefile("${path.module}/mssql_setup.sh.tpl", {
    sa_password        = var.sql_sa_password
    adm_password       = var.sql_adm_s_password
    dev_r_password     = var.sql_dev_r_password
    dev_w_password     = var.sql_dev_w_password
    bitbucket_repo     = var.bitbucket_repo_url
    bitbucket_user     = var.bitbucket_user
    bitbucket_app_pass = var.bitbucket_app_password
  })

  tags = {
    Name = "mssql-terraform-test"
  }
}

output "instance_public_ip" {
  value = aws_instance.mssql.public_ip
}
