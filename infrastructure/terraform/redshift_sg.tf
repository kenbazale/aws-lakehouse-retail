# ---------- Dedicated SG for Redshift Serverless ----------
resource "aws_security_group" "redshift" {
  name        = "${var.project}-${var.env}-redshift-sg"
  description = "Redshift Serverless - bastion access only"
  vpc_id      = var.vpc_id

  # Allow the bastion to connect on 5439
  ingress {
    description     = "Redshift from bastion"
    from_port       = 5439
    to_port         = 5439
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Allow Redshift ENIs to talk to each other (required for internal cluster comms)
  ingress {
    description = "Redshift self-referencing"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-redshift-sg"
  }
}
