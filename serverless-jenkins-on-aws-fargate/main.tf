locals {
  account_id       = data.aws_caller_identity.current.account_id
  region           = data.aws_region.current.name
  jenkins_prefix   = "serverless-jenkins"
  sonarqube_prefix = "serverless-sonarqube"

  tags = {
    team     = "devops"
    solution = "jenkins"
  }
}

// An example of creating a KMS key
resource "aws_kms_key" "efs_kms_key" {
  description = "KMS key used to encrypt Jenkins EFS volume"
}

// Bring your own ACM cert for the Application Load Balancer
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> v2.0"

  domain_name = "${var.jenkins_dns_alias}.${var.route53_domain_name}"
  zone_id     = var.route53_zone_id

  tags = local.tags
}

# Deploy jenkins
module "serverless_jenkins" {
  source                        = "./modules/jenkins_platform"
  name_prefix                   = local.jenkins_prefix
  tags                          = local.tags
  vpc_id                        = var.vpc_id
  efs_kms_key_arn               = aws_kms_key.efs_kms_key.arn
  efs_subnet_ids                = var.efs_subnet_ids
  jenkins_controller_subnet_ids = var.private_subnet_ids
  alb_subnet_ids                = var.alb_subnet_ids
  alb_ingress_allow_cidrs       = ["0.0.0.0/0"]
  alb_acm_certificate_arn       = module.acm.this_acm_certificate_arn
  route53_create_alias          = true
  route53_alias_name            = var.jenkins_dns_alias
  route53_zone_id               = var.route53_zone_id
}

/* -------------------------------------------------------------------------- */
/*                         Deploy serverless_sonarqube                        */
/* -------------------------------------------------------------------------- */

module "acm_sonarqube" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> v2.0"

  domain_name = "${var.sonarqube_dns_alias}.${var.route53_domain_name}"
  zone_id     = var.route53_zone_id

  tags = local.tags
}


module "serverless_sonarqube" {
  source                          = "./modules/sonarqube"
  name_prefix                     = local.sonarqube_prefix
  tags                            = local.tags
  vpc_id                          = var.vpc_id
  efs_kms_key_arn                 = aws_kms_key.efs_kms_key.arn
  efs_subnet_ids                  = var.efs_subnet_ids
  sonarqube_controller_subnet_ids = var.private_subnet_ids
  alb_subnet_ids                  = var.alb_subnet_ids
  alb_ingress_allow_cidrs         = ["0.0.0.0/0"]
  alb_acm_certificate_arn         = module.acm_sonarqube.this_acm_certificate_arn
  route53_create_alias            = true
  route53_alias_name              = var.sonarqube_dns_alias
  route53_zone_id                 = var.route53_zone_id
  sonar_db                        = var.sonar_db
}


