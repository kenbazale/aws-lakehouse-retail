# ============================================================
# SSM Bastion — for reaching private RDS from your laptop
# ============================================================

# ---------- IAM ----------
resource "aws_iam_role" "bastion" {
  name = "${var.project}-${var.env}-bastion-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project}-${var.env}-bastion"
  role = aws_iam_role.bastion.name
}

# ---------- Security group ----------
resource "aws_security_group" "bastion" {
  name        = "${var.project}-${var.env}-bastion-sg"
  description = "SSM bastion - no inbound, outbound only"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Allow the bastion to reach RDS on 5432
resource "aws_security_group_rule" "rds_from_bastion" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.bastion.id
}

# ---------- AMI ----------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------- The bastion ----------
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.nano"
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  # 🔁 FLIP THIS based on Step 0 output:
  #   true  = private subnet + NAT or SSM VPC endpoints available
  #   false = private subnet WITHOUT egress (bastion will fail to register)
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"   # IMDSv2 only
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = aws_kms_key.lakehouse.arn
  }

  tags = {
    Name = "${var.project}-${var.env}-bastion"
  }

  # Don't recreate on AMI refresh — keep it stable
  lifecycle {
    ignore_changes = [ami]
  }
}

# ---------- Outputs ----------
output "bastion_instance_id" {
  value = aws_instance.bastion.id
}

output "bastion_ssm_command" {
  value = "aws ssm start-session --target ${aws_instance.bastion.id} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host=${aws_db_instance.retail.address},portNumber=5432,localPortNumber=5432"
}