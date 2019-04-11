variable "shared" { type = "map" }
terraform { backend "s3" {} }
provider "aws" { region = "${var.shared["region"]}", version = "~> 1.15" }
provider "aws" { alias = "east", region = "us-east-1", version = "~> 1.15" }
data "aws_availability_zones" "all" {}

data "terraform_remote_state" "vpc" { backend = "s3", config = { key = "vpc/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }
data "terraform_remote_state" "base" { backend = "s3", config = { key = "base/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }
data "terraform_remote_state" "ret" { backend = "s3", config = { key = "ret/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }

resource "random_id" "bucket-identifier" {
  byte_length = 8
}

resource "aws_s3_bucket" "photomnemonic-bucket" {
  bucket = "photomnemonic-${var.shared["env"]}-${random_id.bucket-identifier.hex}"
  acl = "private"
}

resource "aws_iam_policy" "photomnemonic-policy" {
  name = "${var.shared["env"]}-photomnemonic-policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Effect": "Allow",
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::${aws_s3_bucket.photomnemonic-bucket.id}/*"
    },
    {
        "Effect": "Allow",
        "Action": "s3:ListBucket",
        "Resource": "arn:aws:s3:::${aws_s3_bucket.photomnemonic-bucket.id}"
    }
  ]
}
EOF
}

resource "aws_iam_role" "photomnemonic-iam-role" {
  name = "${var.shared["env"]}-photomnemonic"
  assume_role_policy = "${var.shared["lambda_role_policy"]}"
  count = "${var.enabled}"
}

resource "aws_iam_role_policy_attachment" "photomnemonic-role-attach" {
  role = "${aws_iam_role.photomnemonic-iam-role.name}"
  policy_arn = "${aws_iam_policy.photomnemonic-policy.arn}"
  count = "${var.enabled}"
}

resource "aws_security_group" "photomnemonic" {
  name = "${var.shared["env"]}-photomnemonic"
  vpc_id = "${data.terraform_remote_state.vpc.vpc_id}"

  ingress {
    from_port = "80"
    to_port = "80"
    protocol = "tcp"
    security_groups = ["${data.terraform_remote_state.ret.ret_security_group_id}"]
  }
}

resource "aws_security_group_rule" "photomnemonic-egress" {
  type = "egress"
  from_port = "80"
  to_port = "80"
  protocol = "tcp"
  security_group_id = "${aws_security_group.photomnemonic.id}"
  source_security_group_id = "${aws_security_group.photomnemonic.id}"
}