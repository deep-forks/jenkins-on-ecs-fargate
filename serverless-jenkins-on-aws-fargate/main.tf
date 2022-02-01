locals {
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name
  name_prefix = "serverless-jenkins"

  tags = {
    team     = "devops"
    solution = "jenkins"
  }
}

// An example of creating a KMS key
resource "aws_kms_key" "efs_kms_key" {
  description = "KMS key used to encrypt Jenkins EFS volume"
}

# // Bring your own ACM cert for the Application Load Balancer
# resource "tls_private_key" "key" {
#   algorithm = "RSA"
# }

# resource "tls_cert_request" "csr" {
#   key_algorithm   = "RSA"
#   private_key_pem = tls_private_key.key.private_key_pem

#   subject {
#     common_name = "${var.jenkins_dns_alias}.${var.route53_domain_name}"
#   }
# }

# resource "aws_acmpca_certificate" "alb_acm_pca_crt" {
#   certificate_authority_arn   = "arn:aws:acm-pca:ap-south-1:262761057346:certificate-authority/4e08900f-8e8e-4573-b127-a52672c69990"
#   certificate_signing_request = tls_cert_request.csr.cert_request_pem
#   signing_algorithm           = "SHA256WITHRSA"
#   validity {
#     type  = "YEARS"
#     value = 2
#   }
# }

# ßDeploy jenkins
module "serverless_jenkins" {
  source                          = "./modules/jenkins_platform"
  name_prefix                     = local.name_prefix
  tags                            = local.tags
  vpc_id                          = var.vpc_id
  efs_kms_key_arn                 = aws_kms_key.efs_kms_key.arn
  efs_subnet_ids                  = var.efs_subnet_ids
  jenkins_controller_subnet_ids   = var.jenkins_controller_subnet_ids
  alb_subnet_ids                  = var.alb_subnet_ids
  alb_ingress_allow_cidrs         = ["0.0.0.0/0"]
  alb_acm_certificate_arn         = "arn:aws:acm:ap-south-1:262761057346:certificate/50335c98-0c6e-4391-b5ff-4d313a4a9f1b"
  route53_create_alias            = true
  route53_alias_name              = var.jenkins_dns_alias
  route53_zone_id                 = var.route53_zone_id
}

