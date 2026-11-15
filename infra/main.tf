data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# AMI oficial de Ubuntu 24.04 publicada por Canonical en SSM Parameter Store
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# ---------------------------------------------------------------- Red
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = var.project }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = var.project }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# El security group por defecto de la VPC queda sin reglas
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}

# ---------------------------------------------------------------- Security groups (minimo privilegio)
resource "aws_security_group" "vm" {
  for_each    = var.vms
  name        = "${var.project}-${each.key}"
  description = "SG del rol ${each.key}"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-${each.key}" }
}

# Entrada: solo el gateway recibe trafico publico (HTTP). Sin SSH en ninguna VPS: acceso por SSM.
resource "aws_vpc_security_group_ingress_rule" "gateway_http" {
  security_group_id = aws_security_group.vm["gateway"].id
  description       = "HTTP publico (demo sin dominio; con dominio usar 443)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "app_from_gateway" {
  security_group_id            = aws_security_group.vm["app"].id
  description                  = "API solo desde el gateway"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.vm["gateway"].id
}

resource "aws_vpc_security_group_ingress_rule" "loki_from_app" {
  security_group_id            = aws_security_group.vm["ops"].id
  description                  = "Loki solo desde la VPS app"
  ip_protocol                  = "tcp"
  from_port                    = 3100
  to_port                      = 3100
  referenced_security_group_id = aws_security_group.vm["app"].id
}

# Salida: solo lo necesario (paquetes, imagenes, SSM) + trafico interno concreto
resource "aws_vpc_security_group_egress_rule" "https" {
  for_each          = aws_security_group.vm
  security_group_id = each.value.id
  description       = "HTTPS (apt, registro de imagenes, endpoints SSM)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "http" {
  for_each          = aws_security_group.vm
  security_group_id = each.value.id
  description       = "HTTP (repositorios apt de Ubuntu)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "dns" {
  for_each          = aws_security_group.vm
  security_group_id = each.value.id
  description       = "DNS hacia el resolver de la VPC"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "gateway_to_app" {
  security_group_id            = aws_security_group.vm["gateway"].id
  description                  = "Proxy hacia la API"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.vm["app"].id
}

resource "aws_vpc_security_group_egress_rule" "app_to_loki" {
  security_group_id            = aws_security_group.vm["app"].id
  description                  = "Envio de logs a Loki"
  ip_protocol                  = "tcp"
  from_port                    = 3100
  to_port                      = 3100
  referenced_security_group_id = aws_security_group.vm["ops"].id
}

# ---------------------------------------------------------------- IAM para SSM
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vm" {
  name               = "${var.project}-vm"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.vm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "vm" {
  name = "${var.project}-vm"
  role = aws_iam_role.vm.name
}

# Bucket temporal que usa el plugin aws_ssm de Ansible para transferir modulos
resource "aws_s3_bucket" "ansible" {
  bucket        = "${var.project}-ssm-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "ansible" {
  bucket                  = aws_s3_bucket.ansible.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ansible" {
  bucket = aws_s3_bucket.ansible.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ansible" {
  bucket = aws_s3_bucket.ansible.id
  rule {
    id     = "expire-temp-objects"
    status = "Enabled"
    filter {}
    expiration {
      days = 1
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "ansible_bucket" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.ansible.arn}/*"]
  }
}

resource "aws_iam_role_policy" "ansible_bucket" {
  name   = "ansible-ssm-bucket"
  role   = aws_iam_role.vm.id
  policy = data.aws_iam_policy_document.ansible_bucket.json
}

# ---------------------------------------------------------------- VPS
resource "aws_instance" "vm" {
  for_each = var.vms

  ami                         = data.aws_ssm_parameter.ubuntu.insecure_value
  instance_type               = each.value
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.vm[each.key].id]
  iam_instance_profile        = aws_iam_instance_profile.vm.name
  associate_public_ip_address = true # necesario para llegar a SSM sin NAT ni VPC endpoints (demo de bajo costo)
  ebs_optimized               = false
  monitoring                  = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 obligatorio
    http_put_response_hop_limit = 1          # los contenedores no alcanzan el IMDS
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = {
    Name = "${var.project}-${each.key}"
    Role = each.key
  }
}
