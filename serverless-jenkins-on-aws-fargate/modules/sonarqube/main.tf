data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

resource "aws_security_group" "efs_security_group" {
  name        = "${var.name_prefix}-efs"
  description = "${var.name_prefix} efs security group"
  vpc_id      = var.vpc_id

  ingress {
    protocol        = "tcp"
    security_groups = [aws_security_group.sonarqube_controller_security_group.id]
    from_port       = 2049
    to_port         = 2049
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}


resource "aws_security_group" "sonarqube_controller_security_group" {
  name        = "${var.name_prefix}-controller"
  description = "${var.name_prefix} controller security group"
  vpc_id      = var.vpc_id

  ingress {
    protocol        = "tcp"
    self            = true
    security_groups = var.alb_create_security_group ? [aws_security_group.alb_security_group[0].id] : var.alb_security_group_ids
    from_port       = var.sonarqube_controller_port
    to_port         = var.sonarqube_controller_port
    description     = "Communication channel to sonarqube leader"
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}


/* -------------------------------------------------------------------------- */
/*                                     ALB                                    */
/* -------------------------------------------------------------------------- */

resource "aws_security_group" "alb_security_group" {
  count = var.alb_create_security_group ? 1 : 0

  name        = "${var.name_prefix}-alb"
  description = "${var.name_prefix} alb security group"
  vpc_id      = var.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = var.alb_ingress_allow_cidrs
    description = "HTTP Public access"
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = var.alb_ingress_allow_cidrs
    description = "HTTPS Public access"
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_lb" "this" {
  name               = replace("${var.name_prefix}-crtl-alb", "_", "-")
  internal           = var.alb_type_internal
  load_balancer_type = "application"
  security_groups    = var.alb_create_security_group ? [aws_security_group.alb_security_group[0].id] : var.alb_security_group_ids
  subnets            = var.alb_subnet_ids

  dynamic "access_logs" {
    for_each = var.alb_enable_access_logs ? [true] : []
    content {
      bucket  = var.alb_access_logs_bucket_name
      prefix  = var.alb_access_logs_s3_prefix
      enabled = true
    }
  }

  tags = var.tags
}

resource "aws_lb_target_group" "this" {
  name        = replace("${var.name_prefix}-crtl", "_", "-")
  port        = var.sonarqube_controller_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled = true
    path    = "/"
  }

  tags       = var.tags
  depends_on = [aws_lb.this]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-Res-2019-08"
  certificate_arn   = var.alb_acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_listener_rule" "redirect_http_to_https" {
  listener_arn = aws_lb_listener.http.arn

  action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    http_header {
      http_header_name = "*"
      values           = ["*"]
    }
  }
}

resource "aws_route53_record" "this" {
  count = var.route53_create_alias ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.route53_alias_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

/* -------------------------------------------------------------------------- */
/*                             EFS including backups                          */
/* -------------------------------------------------------------------------- */

resource "aws_efs_file_system" "this" {
  creation_token = "${var.name_prefix}-fs"

  encrypted                       = var.efs_enable_encryption
  kms_key_id                      = var.efs_kms_key_arn
  performance_mode                = var.efs_performance_mode
  throughput_mode                 = var.efs_throughput_mode
  provisioned_throughput_in_mibps = var.efs_provisioned_throughput_in_mibps

  dynamic "lifecycle_policy" {
    for_each = var.efs_ia_lifecycle_policy != null ? [var.efs_ia_lifecycle_policy] : []
    content {
      transition_to_ia = lifecycle_policy.value
    }
  }

  tags = var.tags
}

resource "aws_efs_access_point" "this" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    gid = 0
    uid = 0
  }
  root_directory {
    path = "/"
    creation_info {
      owner_gid   = var.efs_access_point_uid
      owner_uid   = var.efs_access_point_gid
      permissions = "755"
    }
  }

  tags = var.tags
}


resource "aws_efs_mount_target" "this" {
  // This doesn't work if the VPC is being created where this module is called. Needs work
  for_each = { for subnet in var.efs_subnet_ids : subnet => true }

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.key
  security_groups = [aws_security_group.efs_security_group.id]
}


resource "aws_backup_plan" "this" {
  count = var.efs_enable_backup ? 1 : 0

  name = "${var.name_prefix}-plan"
  rule {
    rule_name           = "${var.name_prefix}-backup-rule"
    target_vault_name   = aws_backup_vault.this[count.index].name
    schedule            = var.efs_backup_schedule
    start_window        = var.efs_backup_start_window
    completion_window   = var.efs_backup_completion_window
    recovery_point_tags = var.tags

    dynamic "lifecycle" {
      for_each = var.efs_backup_cold_storage_after_days != null || var.efs_backup_delete_after_days != null ? [true] : []
      content {
        cold_storage_after = var.efs_backup_cold_storage_after_days
        delete_after       = var.efs_backup_delete_after_days
      }
    }
  }
  tags = var.tags
}

resource "aws_backup_vault" "this" {
  count = var.efs_enable_backup ? 1 : 0

  name = "${var.name_prefix}-vault"
  tags = var.tags
}

resource "aws_backup_selection" "this" {
  count = var.efs_enable_backup ? 1 : 0

  name         = "${var.name_prefix}-selection"
  iam_role_arn = aws_iam_role.aws_backup_role[count.index].arn
  plan_id      = aws_backup_plan.this[count.index].id

  resources = [
    aws_efs_file_system.this.arn
  ]
}

/* -------------------------------------------------------------------------- */
/*                     sonarqube Container Infra (Fargate)                    */
/* -------------------------------------------------------------------------- */

resource "aws_ecs_cluster" "sonarqube_controller" {
  name = "${var.name_prefix}-main"

  tags = var.tags
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "sonarqube_controller" {
  cluster_name = aws_ecs_cluster.sonarqube_controller.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}


resource "aws_cloudwatch_log_group" "sonarqube_controller_log_group" {
  name              = var.name_prefix
  retention_in_days = var.sonarqube_controller_task_log_retention_days
  tags              = var.tags
}


resource "aws_ecs_task_definition" "sonarqube_controller" {
  family = var.name_prefix

  task_role_arn            = var.sonarqube_controller_task_role_arn != null ? var.sonarqube_controller_task_role_arn : aws_iam_role.sonarqube_controller_task_role.arn
  execution_role_arn       = var.ecs_execution_role_arn != null ? var.ecs_execution_role_arn : aws_iam_role.sonarqube_controller_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.sonarqube_controller_cpu
  memory                   = var.sonarqube_controller_memory
  container_definitions = templatefile("${path.module}/templates/sonarqube-controller.json.tpl", {
    name                           = "${var.name_prefix}-controller"
    sonarqube_controller_port      = var.sonarqube_controller_port
    source_volume                  = "${var.name_prefix}-efs"
    container_image                = "sonarqube:10-community"
    sonar_jdbc_url                 = var.sonar_db.jdbc_url
    sonar_jdbc_username            = var.sonar_db.username
    sonar_jdbc_password_secret_arn = var.sonar_db.password_secret_arn
    log_group                      = aws_cloudwatch_log_group.sonarqube_controller_log_group.name
    region                         = local.region
    memory                         = var.sonarqube_controller_memory
    cpu                            = var.sonarqube_controller_cpu
  })

  volume {
    name = "${var.name_prefix}-efs"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.this.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.this.id
        iam             = "ENABLED"
      }
    }
  }

  tags = var.tags
}

resource "aws_ecs_service" "sonarqube_controller" {
  name = "${var.name_prefix}-controller"

  task_definition  = aws_ecs_task_definition.sonarqube_controller.arn
  cluster          = aws_ecs_cluster.sonarqube_controller.id
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "1.4.0"

  // Assuming we cannot have more than one instance at a time. Ever.
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0


  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "${var.name_prefix}-controller"
    container_port   = var.sonarqube_controller_port
  }

  network_configuration {
    subnets          = var.sonarqube_controller_subnet_ids
    security_groups  = [aws_security_group.sonarqube_controller_security_group.id]
    assign_public_ip = false
  }

  depends_on = [aws_lb_listener.https]
}

