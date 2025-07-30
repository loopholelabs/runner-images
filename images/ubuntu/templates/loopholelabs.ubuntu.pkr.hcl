packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "1.4.5"
    }

    amazon = {
      version = "1.3.3"
      source  = "github.com/hashicorp/amazon"
    }

    docker = {
      version = "1.1.0"
      source  = "github.com/hashicorp/docker"
    }
  }

  # Require MPL-2.0 version of Packer.
  required_version = "< 1.10.0"
}

locals {
  managed_image_name      = var.managed_image_name != "" ? var.managed_image_name : "packer-${var.image_os}-${var.image_version}"
  managed_image_full_name = var.managed_image_version != "" ? "${local.managed_image_name}-${var.managed_image_version}" : local.managed_image_name

  oci_image_name = var.oci_image_name_prefix != "" ? "${var.oci_image_name_prefix}/${local.managed_image_name}" : local.managed_image_name
  oci_image_tags = compact(concat([var.managed_image_version], var.oci_image_tags))

  aws_base_ami_map = {
    "ubuntu22" = {
      ami_name_filter = "ubuntu/images/*ubuntu-jammy-22.04-amd64-server-*"
      os_disk_size_gb = coalesce(var.os_disk_size_gb, 75)
    },
    "ubuntu24" = {
      ami_name_filter = "ubuntu/images/*ubuntu-noble-24.04-amd64-server-*"
      os_disk_size_gb = coalesce(var.os_disk_size_gb, 75)
    },
  }
  aws_base_ami = local.aws_base_ami_map[var.image_os]

  oci_base_image_map = {
    "ubuntu22" = {
      name = "Dockerfile-ubuntu-22.04"
    },
    "ubuntu24" = {
      name = "Dockerfile-ubuntu-24.04"
    },
  }
  oci_base_image = local.oci_base_image_map[var.image_os]
}

variable "managed_image_version" {
  type    = string
  default = ""
}

# AWS Variables.
variable "aws_build_region" {
  type    = string
  default = "us-west-2"
}

variable "aws_ami_regions" {
  type    = list(string)
  default = []
}

variable "aws_tags" {
  type    = map(string)
  default = {}
}

# OCI Variables.
variable "oci_ecr_server" {
  type    = string
  default = ""
}

variable "oci_image_name_prefix" {
  type    = string
  default = ""
}

variable "oci_image_tags" {
  type    = list(string)
  default = []
}

variable "oci_tmp_folder" {
  type    = string
  default = "/tmp/packer-oci-tmp"
}

source "amazon-ebs" "image" {
  ami_name      = local.managed_image_full_name
  instance_type = "m5zn.xlarge"
  region        = var.aws_build_region
  ami_regions   = var.aws_ami_regions
  ssh_username  = "ubuntu"
  tags          = var.aws_tags

  source_ami_filter {
    filters = {
      name                = local.aws_base_ami.ami_name_filter
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = local.aws_base_ami.os_disk_size_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }

  aws_polling {
    delay_seconds = 60
    max_attempts  = 120
  }
}

source "docker" "image" {
  build {
    path = "${path.root}/${local.oci_base_image.name}"
  }

  docker_path = "podman"
  privileged  = true
  commit      = true

  run_command = [
    "--detach",
    "--interactive",
    "--tty",
    "--systemd=always",
    "--entrypoint=/lib/systemd/systemd",
    "--log-driver=none",
    "--",
    "{{.Image}}",
  ]

  volumes = {
    "${var.oci_tmp_folder}" = "/tmp",
  }
}
