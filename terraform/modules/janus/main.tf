variable "shared" { type = "map" }
terraform { backend "s3" {} }
provider "aws" { region = "${var.shared["region"]}", version = "~> 1.15" }
provider "aws" { alias = "east", region = "us-east-1", version = "~> 1.15" }
data "aws_availability_zones" "all" {}

data "terraform_remote_state" "vpc" { backend = "s3", config = { key = "vpc/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }
data "terraform_remote_state" "base" { backend = "s3", config = { key = "base/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }
data "terraform_remote_state" "bastion" { backend = "s3", config = { key = "bastion/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }
data "terraform_remote_state" "hab" { backend = "s3", config = { key = "hab/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }
data "terraform_remote_state" "ret" { backend = "s3", config = { key = "ret/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }
data "terraform_remote_state" "ret-db" { backend = "s3", config = { key = "ret-db/terraform.tfstate", bucket = "${var.shared["state_bucket"]}", region = "${var.shared["region"]}", dynamodb_table = "${var.shared["dynamodb_table"]}", encrypt = "true" } }

data "aws_ami" "janus-ami" {
  most_recent = true
  owners = ["self"]

  filter {
    name = "name"
    values = ["janus-*"]
  }
}

resource "random_id" "bucket-identifier" {
  byte_length = 8
}

# Logs bucket
resource "aws_s3_bucket" "janus-bucket" {
  bucket = "janus.reticulum-${var.shared["env"]}-${random_id.bucket-identifier.hex}"
  acl = "private"
}

resource "aws_security_group" "janus" {
  name = "${var.shared["env"]}-janus"
  vpc_id = "${data.terraform_remote_state.vpc.vpc_id}"

  egress {
    from_port = "80"
    to_port = "80"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = "443"
    to_port = "443"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # WebRTC RTP egress
  egress {
    from_port = "0"
    to_port = "65535"
    protocol = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Janus HTTPS
  ingress {
    from_port = "${var.janus_https_port}"
    to_port = "${var.janus_https_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Janus Websockets
  ingress {
    from_port = "${var.janus_wss_port}"
    to_port = "${var.janus_wss_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Janus Admin via bastion
  ingress {
    from_port = "${var.janus_admin_port}"
    to_port = "${var.janus_admin_port}"
    protocol = "tcp"
    security_groups = ["${data.terraform_remote_state.bastion.bastion_security_group_id}"]
  }

  # Janus Admin via reticulum
  ingress {
    from_port = "${var.janus_admin_port}"
    to_port = "${var.janus_admin_port}"
    protocol = "tcp"
    security_groups = ["${data.terraform_remote_state.ret.ret_security_group_id}"]
  }

  # Janus RTP-over-UDP
  ingress {
    from_port = "${var.janus_rtp_port_from}"
    to_port = "${var.janus_rtp_port_to}"
    protocol = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Janus RTP-over-TCP
  ingress {
    from_port = "${var.janus_rtp_port_from}"
    to_port = "${var.janus_rtp_port_to}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # TURN TCP TLS
  ingress {
    from_port = "${var.coturn_public_tls_port}"
    to_port = "${var.coturn_public_tls_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # TURN DTLS
  ingress {
    from_port = "${var.coturn_public_tls_port}"
    to_port = "${var.coturn_public_tls_port}"
    protocol = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    from_port = "22"
    to_port = "22"
    protocol = "tcp"
    security_groups = ["${data.terraform_remote_state.bastion.bastion_security_group_id}"]
  }

  # ICMP
  ingress {
    from_port = "-1"
    to_port = "-1"
    protocol = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ICMP
  ingress {
    from_port = "-1"
    to_port = "-1"
    protocol = "icmpv6"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NTP
  egress {
    from_port = "123"
    to_port = "123"
    protocol = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # InfluxDB
  egress {
    from_port = "8086"
    to_port = "8086"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "janus" {
  name = "${var.shared["env"]}-janus"
  assume_role_policy = "${var.shared["ec2_role_policy"]}"
}

resource "aws_iam_role_policy_attachment" "bastion-base-policy" {
  role = "${aws_iam_role.janus.name}"
  policy_arn = "${data.terraform_remote_state.base.base_policy_arn}"
}

resource "aws_iam_policy" "janus-bucket-policy" {
  name = "${var.shared["env"]}-janus-bucket-policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Effect": "Allow",
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::${aws_s3_bucket.janus-bucket.id}/*"
    }
  ]
}
EOF
}

resource "aws_s3_bucket_public_access_block" "janus-bucket-block" {
  bucket = "${aws_s3_bucket.janus-bucket.id}"

  block_public_acls   = true
  block_public_policy = true
}

resource "aws_iam_role_policy_attachment" "janus-role-attach" {
  role = "${aws_iam_role.janus.name}"
  policy_arn = "${aws_iam_policy.janus-bucket-policy.arn}"
}

resource "aws_iam_instance_profile" "janus" {
  name = "${var.shared["env"]}-janus"
  role = "${aws_iam_role.janus.id}"
}

resource "aws_launch_configuration" "janus" {
  image_id = "${data.aws_ami.janus-ami.id}"
  instance_type = "${var.janus_instance_type}"
  security_groups = [
    "${aws_security_group.janus.id}",
    "${data.terraform_remote_state.hab.hab_ring_security_group_id}",
    "${data.terraform_remote_state.ret-db.ret_db_consumer_security_group_id}",
  ]
  key_name = "${data.terraform_remote_state.base.mr_ssh_key_id}"
  iam_instance_profile = "${aws_iam_instance_profile.janus.id}"
  associate_public_ip_address = true
  lifecycle { create_before_destroy = true }
  root_block_device { volume_size = 128 }
  user_data = <<EOF
#!/usr/bin/env bash
while ! nc -z localhost 9632 ; do sleep 1; done
systemctl restart systemd-sysctl.service
# Forward 8443 to 443 for janus websockets, 5349 to 80 for TURN DTLS/TCP TLS
sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 5349
sudo iptables -t nat -A PREROUTING -p udp --dport 80 -j REDIRECT --to-port 5349

sudo mkdir -p /hab/user/janus-gateway/config
sudo mkdir -p /hab/user/coturn/config

sudo cat > /etc/cron.d/janus-restart << EOCRON
0 10 * * * hab PID=\$(head -n 1 /hab/svc/janus-gateway/var/janus-self.pid) ; kill \$PID ; sleep 10 ; kill -0 \$PID 2> /dev/null && kill -9 \$PID
EOCRON

/etc/init.d/cron reload

sudo cat > /hab/user/janus-gateway/config/user.toml << EOTOML
[transports.http]
admin_ip = "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
EOTOML

sudo cat > /hab/user/coturn/config/user.toml << EOTOML
[general]
listening_ip = "0.0.0.0"
external_ip = "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
relay_ip = "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
allowed_peer_ip = "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
EOTOML

sudo sed -i "s/#RateLimitBurst=1000/RateLimitBurst=5000/" /etc/systemd/journald.conf
sudo systemctl restart systemd-journald

mkdir -p /hab/svc/janus-gateway/files
mkdir -p /hab/svc/coturn/files

chown -R hab:hab /hab/svc/janus-gateway
chown -R hab:hab /hab/svc/coturn

aws s3 cp s3://${aws_s3_bucket.janus-bucket.id}/janus-gateway-files.tar.gz.gpg .
gpg2 -d --pinentry-mode=loopback --passphrase-file=/hab/svc/janus-gateway/files/gpg-file-key.txt janus-gateway-files.tar.gz.gpg | tar xz -C /hab/svc/janus-gateway/files
rm janus-gateway-files.tar.gz.gpg
aws s3 cp s3://${aws_s3_bucket.janus-bucket.id}/coturn-files.tar.gz.gpg .
gpg2 -d --pinentry-mode=loopback --passphrase-file=/hab/svc/coturn/files/gpg-file-key.txt coturn-files.tar.gz.gpg | tar xz -C /hab/svc/coturn/files
rm coturn-files.tar.gz.gpg

chown -R hab:hab /hab/svc/janus-gateway/files
chown -R hab:hab /hab/svc/coturn/files

sudo /usr/bin/hab svc load mozillareality/janus-gateway --strategy ${var.janus_restart_strategy} --url https://bldr.habitat.sh --channel ${var.janus_channel}
sudo /usr/bin/hab svc load mozillareality/coturn --strategy ${var.coturn_restart_strategy} --url https://bldr.habitat.sh --channel ${var.janus_channel}
sudo /usr/bin/hab svc load mozillareality/telegraf --strategy at-once --url https://bldr.habitat.sh --channel stable
EOF
}

resource "aws_autoscaling_group" "janus" {
  name = "${var.shared["env"]}-janus"
  launch_configuration = "${aws_launch_configuration.janus.id}"
  availability_zones = ["${data.aws_availability_zones.all.names}"]
  vpc_zone_identifier = ["${data.terraform_remote_state.vpc.public_subnet_ids}"]

  min_size = "${var.min_janus_servers}"
  max_size = "${var.max_janus_servers}"

  lifecycle { create_before_destroy = true }
  tag { key = "env", value = "${var.shared["env"]}", propagate_at_launch = true }
  tag { key = "host-type", value = "${var.shared["env"]}-janus", propagate_at_launch = true }
  tag { key = "hab-ring", value = "${var.shared["env"]}", propagate_at_launch = true }
}

resource "aws_launch_configuration" "janus-smoke" {
  image_id = "${data.aws_ami.janus-ami.id}"
  instance_type = "${var.smoke_janus_instance_type}"
  security_groups = [
    "${aws_security_group.janus.id}",
    "${data.terraform_remote_state.hab.hab_ring_security_group_id}",
    "${data.terraform_remote_state.ret-db.ret_db_consumer_security_group_id}",
  ]
  key_name = "${data.terraform_remote_state.base.mr_ssh_key_id}"
  iam_instance_profile = "${aws_iam_instance_profile.janus.id}"
  associate_public_ip_address = true
  lifecycle { create_before_destroy = true }
  root_block_device { volume_size = 128 }
  user_data = <<EOF
#!/usr/bin/env bash
while ! nc -z localhost 9632 ; do sleep 1; done
systemctl restart systemd-sysctl.service
# Forward 8443 to 443 for janus websockets, 5349 to 80 for TURN TLS
sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 5349
sudo iptables -t nat -A PREROUTING -p udp --dport 80 -j REDIRECT --to-port 5349

sudo mkdir -p /hab/user/janus-gateway/config
sudo mkdir -p /hab/user/coturn/config

sudo cat > /etc/cron.d/janus-restart << EOCRON
0 10 * * * hab PID=\$(head -n 1 /hab/svc/janus-gateway/var/janus-self.pid) ; kill \$PID ; sleep 10 ; kill -0 \$PID 2> /dev/null && kill -9 \$PID
EOCRON

/etc/init.d/cron reload

sudo cat > /hab/user/janus-gateway/config/user.toml << EOTOML
[transports.http]
admin_ip = "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
EOTOML

sudo cat > /hab/user/coturn/config/user.toml << EOTOML
[general]
listening_ip = "0.0.0.0"
external_ip = "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
relay_ip = "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
allowed_peer_ip = "$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
EOTOML

sudo sed -i "s/#RateLimitBurst=1000/RateLimitBurst=5000/" /etc/systemd/journald.conf
sudo systemctl restart systemd-journald

mkdir -p /hab/svc/janus-gateway/files
mkdir -p /hab/svc/coturn/files

chown -R hab:hab /hab/svc/janus-gateway
chown -R hab:hab /hab/svc/coturn

aws s3 cp s3://${aws_s3_bucket.janus-bucket.id}/janus-gateway-files.tar.gz.gpg .
gpg2 -d --pinentry-mode=loopback --passphrase-file=/hab/svc/janus-gateway/files/gpg-file-key.txt janus-gateway-files.tar.gz.gpg | tar xz -C /hab/svc/janus-gateway/files
rm janus-gateway-files.tar.gz.gpg
aws s3 cp s3://${aws_s3_bucket.janus-bucket.id}/coturn-files.tar.gz.gpg .
gpg2 -d --pinentry-mode=loopback --passphrase-file=/hab/svc/coturn/files/gpg-file-key.txt coturn-files.tar.gz.gpg | tar xz -C /hab/svc/coturn/files
rm coturn-files.tar.gz.gpg

chown -R hab:hab /hab/svc/janus-gateway/files
chown -R hab:hab /hab/svc/coturn/files

sudo /usr/bin/hab svc load mozillareality/janus-gateway --strategy ${var.janus_restart_strategy} --url https://bldr.habitat.sh --channel ${var.janus_channel}
sudo /usr/bin/hab svc load mozillareality/coturn --strategy ${var.coturn_restart_strategy} --url https://bldr.habitat.sh --channel ${var.janus_channel}
sudo /usr/bin/hab svc load mozillareality/telegraf --strategy at-once --url https://bldr.habitat.sh --channel stable
EOF
}
