variable "app" {
  type = any
}

variable "config" {
  type = any
}

variable "server" {
  type = any
}

variable "network" {
  type = any
}

variable "zone" {
  type        = string
  description = "Zone where the instances should be created. If not specified, instances will be spread across available zones in the region."
  default     = null
}