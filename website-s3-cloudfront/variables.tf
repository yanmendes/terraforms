variable "host" {
  type    = string
}

variable "domain" {
  type    = string
  # default = "yanmendes.dev."
}

variable "s3Key" {
  type    = string
  default = "123-super-duper-secret-321"
}

variable "tags" {
  type   = map
  default = {
    Owner = "Yan Mendes"
  }
}