variable "janus_instance_type" {
  description = "Janus server instance type"
}

variable "smoke_janus_instance_type" {
  description = "Smoke Janus server instance type"
}

variable "janus_https_port" {
  description = "Janus signalling secure HTTP port"
}

variable "janus_wss_port" {
  description = "Janus signalling secure Websockets port"
}

variable "janus_admin_port" {
  description = "Janus HTTP admin port"
}

variable "janus_rtp_port_from" {
  description = "Janus RTP port from"
}

variable "janus_rtp_port_to" {
  description = "Janus RTP port to"
}

variable "min_janus_servers" {
  description = "Minimum number of janus servers to run"
}

variable "max_janus_servers" {
  description = "Maximum number of janus servers to run"
}

variable "janus_channel" {
  description = "Distribution channel for janus on non-smoke servers"
}

variable "janus_restart_strategy" {
  description = "Habitat restart strategy for Janus"
}

variable "coturn_public_tls_port" {
  description = "Public TLS port for coturn"
}

variable "coturn_port_from" {
  description = "Lower relay port for coturn"
}

variable "coturn_port_to" {
  description = "Upper relay port for coturn"
}

variable "coturn_channel" {
  description = "Distribution channel for coturn on non-smoke servers"
}

variable "coturn_restart_strategy" {
  description = "Habitat restart strategy for coturn"
}
