variable "host" {
  type    = string
}

variable "domain" {
  type    = string
  # default = "yanmendes.dev."
}

variable "sshKey" {
  type    = string
}

variable "tags" {
  type   = map
  default = {
    Owner = "Yan Mendes"
  }
}
