provider "aws" {
  region = "us-west-1"
}

module "vpc" {
  source = "git::ssh://git@gitlab.et-scm.com/elsevier-core-engineering/rp-terraform-vpc.git?ref=2.2.3"

  global_phz_domain           = "${var.global_phz_domain}"
  global_availability_zones   = "${var.global_availability_zones}"
  global_public_subnets       = "${var.global_public_subnets}"
  global_private_subnets      = "${var.global_private_subnets}"
  global_elsevier_cidr_blocks = "${var.global_elsevier_cidr_blocks}"

  vpc_subnet          = "${var.vpc_subnet_cidr}"
  vpc_name            = "${var.vpc_name}"
  vpc_environment_tag = "${var.vpc_environment_tag}"
  vpc_product_tag     = "${var.vpc_product_tag}"
  vpc_contact_tag     = "${var.vpc_contact_tag}"
}

/*module "container_repository_ui" {
  source = "git::ssh://git@gitlab.et-scm.com/elsevier-core-engineering/rp-terraform-ecr.git"

  ecr_repository_name = "${var.ecr_ui_repository_name}"
}*/

module "demo_ecs" {
  source                        = "git::ssh://git@gitlab.et-scm.com/NGUYEN1/hs-terraform-edtech-ecs-cluster.git?ref=0.2.0"
  global_region                 = "${var.aws_region}"
  global_vpc_id                 = "${module.vpc.vpc_id}"
  ecs_cluster_asg_subnets       = "${module.vpc.private_subnets}"
  ecs_cluster_keypair           = "shobha_tutorial"
  ecs_cluster_tag_product       = "${var.global_tag_product}"
  ecs_cluster_tag_sub_product   = "${var.global_tag_sub_product}"
  ecs_cluster_tag_contact       = "s.lakshminarayana@elsevier.com"
  ecs_cluster_tag_cost_code     = "${var.global_tag_cost_code}"
  ecs_cluster_tag_environment   = "demo"
  ecs_cluster_tag_orchestration = "${var.global_tag_orchestration}"
  ecs_cluster_instance_tier     = "ontotext"
  ecs_cluster_name_tag          = "ecs_cluster"
  ecs_cluster_instance_type     = "m4.large"
  ecs_cluster_asg_max_size      = 2
  ecs_cluster_asg_min_size      = 0
  ecs_cluster_asg_desired_size  = 1
}

module public_lb_sg {
  source = "terraform-aws-modules/security-group/aws"

  name        = "eols-stage-public-alb"
  description = "SG that allow incoming HTTP and HTTPS connections from everywhere to our public ALBs"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress_rules = [
    "https-443-tcp",
    "http-80-tcp",
  ]

  ingress_cidr_blocks = [
    "0.0.0.0/0",
  ]

  tags = "${map(
    "Environment",  "demo",
    "Product",      "${var.global_tag_product}",
    "Subproduct",   "${var.global_tag_sub_product}",
    "Contact",      "s.lakshminarayana@elsevier.com",
    "Description",  "SG that allow incoming HTTP and HTTPS connections from everywhere to our public ALBs"
  )}"
}

module demo_alb {
  source             = "terraform-aws-modules/alb/aws"
  load_balancer_name = "demo-alb-${var.global_tag_product}-development"

  security_groups = [
    "${module.vpc.inbound_http_security_group}",     # HTTP from Elsevier
    "${module.vpc.inbound_https_security_group}",    # HTTPS from Elsevier
    "${module.demo_ecs.public_lb_sg}",
    "${module.public_lb_sg.this_security_group_id}",
  ]

  logging_enabled = false

  subnets = [
    "${split(",", module.vpc.public_subnets)}",
  ]

  tags = "${map(
    "Environment",  "demo",
    "Product",      "${var.global_tag_product}",
    "Subproduct",   "${var.global_tag_sub_product}",
    "Contact",      "s.lakshminarayana@elsevier.com",
    "Description",  "ALB for Demo"
  )}"

  vpc_id = "${module.vpc.vpc_id}"

  http_tcp_listeners = [
    {
      port     = 80
      protocol = "HTTP"
    },
  ]

  http_tcp_listeners_count = 1

  https_listeners = [
    {
      certificate_arn = "arn:aws:acm:us-west-1:240595173262:certificate/16c443c9-fd65-418a-8d90-c1af59c87051"
      port            = "443"
      ssl_policy      = "ELBSecurityPolicy-TLS-1-2-2017-01"
    },
  ]

  https_listeners_count = 1

  target_groups = [
    {
      name             = "green-demo"
      backend_protocol = "HTTP"
      backend_port     = 80
    },
    {
      name             = "blue-demo"
      backend_protocol = "HTTP"
      backend_port     = 80
    },
  ]

  target_groups_count = "2"
}

module "demo_green" {
  source = "git::ssh://git@gitlab.et-scm.com/edtech-devops/hs-terraform-anr-ecs-service.git?ref=stage-0.1.2"

  global_vpc_id                = "${module.vpc.vpc_id}"
  edtech_service_name          = "demo-green"
  edtech_cluster_name          = "${module.demo_ecs.ecs_cluster_name}"
  edtech_target_group_arn      = "${module.demo_alb.target_group_arns[0]}"
  edtech_service_docker_image  = "240595173262.dkr.ecr.us-west-1.amazonaws.com/demo_app:23"
  edtech_tag_product           = "${var.global_tag_product}"
  edtech_tag_sub_product       = "${var.global_tag_sub_product}"
  edtech_tag_contact           = "s.lakshminarayana@elsevier.com"
  edtech_tag_cost_code         = "${var.global_tag_cost_code}"
  edtech_tag_environment       = "demo"
  edtech_tag_orchestration     = "${var.global_tag_orchestration}"
  edtech_service_docker_memory = 256

  edtech_service_container_environments = [
    {
      name  = "NODE_ENV"
      value = "production"
    },
  ]

  edtech_service_docker_port_mappings = [
    {
      containerPort = 3000
      hostPort      = 0
      protocol      = "tcp"
    },
  ]
}

module "demo_blue" {
  source = "git::ssh://git@gitlab.et-scm.com/edtech-devops/hs-terraform-anr-ecs-service.git?ref=stage-0.1.2"

  global_vpc_id                = "${module.vpc.vpc_id}"
  edtech_service_name          = "demo-blue"
  edtech_cluster_name          = "${module.demo_ecs.ecs_cluster_name}"
  edtech_target_group_arn      = "${module.demo_alb.target_group_arns[1]}"
  edtech_service_docker_image  = "240595173262.dkr.ecr.us-west-1.amazonaws.com/demo_app:ac5d382ece1e99101a25fdf996a5f82c532a27d4"
  edtech_tag_product           = "${var.global_tag_product}"
  edtech_tag_sub_product       = "${var.global_tag_sub_product}"
  edtech_tag_contact           = "s.lakshminarayana@elsevier.com"
  edtech_tag_cost_code         = "${var.global_tag_cost_code}"
  edtech_tag_environment       = "demo"
  edtech_tag_orchestration     = "${var.global_tag_orchestration}"
  edtech_service_docker_memory = 512

  edtech_service_container_environments = [
    {
      name  = "NODE_ENV"
      value = "QA"
    },
  ]

  edtech_service_docker_port_mappings = [
    {
      containerPort = 3000
      hostPort      = 0
      protocol      = "tcp"
    },
  ]
}

module "demo_assignment" {
  source = "git::ssh://git@gitlab.et-scm.com/NGUYEN1/hs-terraform-edtech-assignment.git?ref=c9f66"

  assignment_host_based_rules = [
    {
      listener_arn     = "${module.demo_alb.https_listener_arns[0]}"
      target_group_arn = "${module.demo_alb.target_group_arns[1]}"
      host_name        = "${module.demo_blue_public_alias_api.route53_record_fqdn}"
    },
    {
      listener_arn     = "${module.demo_alb.https_listener_arns[0]}"
      target_group_arn = "${module.demo_alb.target_group_arns[0]}"
      host_name        = "${module.demo_green_public_alias_api.route53_record_fqdn}"
    },
    {
      //main routing to green
      listener_arn     = "${module.demo_alb.https_listener_arns[0]}"
      target_group_arn = "${module.demo_alb.target_group_arns[1]}"
      host_name        = "${module.demo_main_public_alias_api.route53_record_fqdn}"
    },
    {
      //main routing to blue
      listener_arn     = "${module.demo_alb.https_listener_arns[0]}"
      target_group_arn = "${module.demo_alb.target_group_arns[0]}"
      host_name        = "${module.demo_main_public_alias_api.route53_record_fqdn}"
    },
  ]
}

locals {
  demo_zone_id = "Z26XJJST2LTO8U"
}

module "demo_blue_public_alias_api" {
  source = "git::ssh://git@gitlab.et-scm.com/elsevier-core-engineering/rp-terraform-route53-alias.git?ref=1.0.0"

  route53_primary_zone_id    = "${local.demo_zone_id}"
  route53_record_name        = "blue"
  route53_resource_dns_name  = "${module.demo_alb.dns_name}"
  route53_resource_zone_id   = "${module.demo_alb.load_balancer_zone_id}"
  route53_eval_target_health = true
}

module "demo_green_public_alias_api" {
  source = "git::ssh://git@gitlab.et-scm.com/elsevier-core-engineering/rp-terraform-route53-alias.git?ref=1.0.0"

  route53_primary_zone_id    = "${local.demo_zone_id}"
  route53_record_name        = "green"
  route53_resource_dns_name  = "${module.demo_alb.dns_name}"
  route53_resource_zone_id   = "${module.demo_alb.load_balancer_zone_id}"
  route53_eval_target_health = true
}

module "demo_main_public_alias_api" {
  source = "git::ssh://git@gitlab.et-scm.com/elsevier-core-engineering/rp-terraform-route53-alias.git?ref=1.0.0"

  route53_primary_zone_id    = "${local.demo_zone_id}"
  route53_record_name        = "www"
  route53_resource_dns_name  = "${module.demo_alb.dns_name}"
  route53_resource_zone_id   = "${module.demo_alb.load_balancer_zone_id}"
  route53_eval_target_health = true
}
