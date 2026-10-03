data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

locals {
  az_names = slice(data.aws_availability_zones.available.names, 0, 3)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  count = 3

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.az_names[count.index]
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count = 3

  vpc_id            = aws_vpc.this.id
  availability_zone = local.az_names[count.index]
  cidr_block        = var.private_subnet_cidrs[count.index]

  tags = {
    Name = "${var.name_prefix}-private-${count.index + 1}"
  }
}

# One NAT Gateway PER AZ (not shared) -- with a single shared NAT, an outage in
# the AZ holding it would cut outbound internet access for the *other* AZ's
# private subnet too, undermining the whole point of spreading nodes/tasks
# across 2 AZs for fault tolerance. Costs roughly double the single-NAT setup,
# acceptable for a "spin up for a few hours" learning cluster.
resource "aws_eip" "nat" {
  count = 3

  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "this" {
  count = 3

  subnet_id     = aws_subnet.public[count.index].id
  allocation_id = aws_eip.nat[count.index].id

  tags = {
    Name = "${var.name_prefix}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.this]
}

# Public routing is identical regardless of AZ (0.0.0.0/0 -> IGW), so one
# shared route table for both public subnets is fine -- no per-AZ fault
# isolation benefit to be had here since IGW itself isn't AZ-scoped.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = 3

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private routing DOES need to be per-AZ now: each private subnet's default
# route points at the NAT Gateway in its OWN AZ, not a shared one.
resource "aws_route_table" "private" {
  count = 3

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = {
    Name = "${var.name_prefix}-private-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private" {
  count = 3

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Gateway endpoint (S3/DynamoDB only support this type): free, no hourly charge and
# no per-GB data processing charge, unlike an Interface endpoint or routing this
# traffic through the NAT Gateway. Works by adding routes to the private route
# tables, not by attaching an ENI -- every private subnet's backend pods reach
# DynamoDB over AWS's own network instead of via NAT, at zero extra cost.
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = {
    Name = "${var.name_prefix}-dynamodb-endpoint"
  }
}
