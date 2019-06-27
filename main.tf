module "default_label" {
  source     = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.2.1"
  name       = "${var.name}"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  attributes = "${var.attributes}"
}

module "ecr" {
  enabled    = "${var.codepipeline_enabled}"
  source     = "git::https://github.com/cloudposse/terraform-aws-ecr.git?ref=tags/0.6.0"
  name       = "${var.name}"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  attributes = "${compact(concat(var.attributes, list("ecr")))}"
  max_image_count = "30"
}

resource "aws_cloudwatch_log_group" "app" {
  name = "${module.default_label.id}"
  tags = "${module.default_label.tags}"
}

module "codedeploy_label" {
  source     = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=0.2.1"
  attributes = ["${compact(concat(var.attributes, list("codedeploy")))}"]
  delimiter  = "${var.delimiter}"
  name       = "${var.name}"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  tags       = "${var.tags}"
}

module "codedeploy_group_label" {
  source     = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=0.2.1"
  attributes = ["${compact(concat(var.attributes, list("codedeploy", "group")))}"]
  delimiter  = "${var.delimiter}"
  name       = "${var.name}"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  tags       = "${var.tags}"
}

module "alb_ingress_blue" {
  source            = "git::https://github.com/cloudposse/terraform-aws-alb-ingress.git?ref=tags/0.7.0"
  name              = "${var.name}"
  namespace         = "${var.namespace}"
  stage             = "${var.stage}"
  attributes        = ["${var.attributes}", "blue"]
  vpc_id            = "${var.vpc_id}"
  port              = "${var.container_port}"
  health_check_path = "${var.alb_ingress_healthcheck_path}"

  unauthenticated_paths = ["${var.alb_ingress_unauthenticated_paths}"]
  unauthenticated_hosts = ["${var.alb_ingress_unauthenticated_hosts}"]

  unauthenticated_priority = "${var.alb_ingress_listener_unauthenticated_priority}"

  unauthenticated_listener_arns       = ["${var.alb_http_listener_arn}", "${var.alb_ssl_listener_arn}"]
  unauthenticated_listener_arns_count = "${var.alb_ingress_prod_listener_arns_count}"
}

module "alb_ingress_green" {
  source            = "git::https://github.com/cloudposse/terraform-aws-alb-ingress.git?ref=tags/0.7.0"
  name              = "${var.name}"
  namespace         = "${var.namespace}"
  stage             = "${var.stage}"
  attributes        = ["${var.attributes}", "green"]
  vpc_id            = "${var.vpc_id}"
  port              = "${var.container_port}"
  health_check_path = "${var.alb_ingress_healthcheck_path}"

  unauthenticated_paths = ["${var.alb_ingress_unauthenticated_paths}"]
  unauthenticated_hosts = ["${var.alb_ingress_unauthenticated_hosts}"]

  unauthenticated_priority = "${var.alb_ingress_listener_unauthenticated_priority}"

  unauthenticated_listener_arns       = ["${var.alb_test_listener_arn}"]
  unauthenticated_listener_arns_count = "1"
}

module "container_definition" {
  source                       = "git::https://github.com/cloudposse/terraform-aws-ecs-container-definition.git?ref=tags/0.9.1"
  container_name               = "${module.default_label.id}"
  container_image              = "${var.container_image}"
  container_memory             = "${var.container_memory}"
  container_memory_reservation = "${var.container_memory_reservation}"
  container_cpu                = "${var.container_cpu}"
  healthcheck                  = "${var.healthcheck}"
  environment                  = "${var.environment}"
  port_mappings                = "${var.port_mappings}"

  log_options = {
    "awslogs-region"        = "${var.aws_logs_region}"
    "awslogs-group"         = "${aws_cloudwatch_log_group.app.name}"
    "awslogs-stream-prefix" = "${var.name}"
  }
}

module "ecs_alb_service_task" {
  source                            = "git::https://github.com/GMADLA/terraform-aws-ecs-alb-service-task.git?ref=tags/0.12.0"
  name                              = "${var.name}"
  namespace                         = "${var.namespace}"
  stage                             = "${var.stage}"
  attributes                        = "${var.attributes}"
  alb_target_group_arn              = "${module.alb_ingress_blue.target_group_arn}"
  container_definition_json         = "${module.container_definition.json}"
  container_name                    = "${module.default_label.id}"
  desired_count                     = "${var.desired_count}"
  health_check_grace_period_seconds = "${var.health_check_grace_period_seconds}"
  task_cpu                          = "${var.container_cpu}"
  task_memory                       = "${var.container_memory}"
  ecs_cluster_arn                   = "${var.ecs_cluster_arn}"
  launch_type                       = "${var.launch_type}"
  vpc_id                            = "${var.vpc_id}"
  security_group_ids                = ["${var.ecs_security_group_ids}"]
  subnet_ids                        = ["${var.ecs_private_subnet_ids}"]
  container_port                    = "${var.container_port}"
  deployment_type                   = "CODE_DEPLOY"
}

# BLUE/GREEN ✖‿✖
resource "aws_codedeploy_app" "default" {
  compute_platform = "ECS"
  name             = "${module.codedeploy_label.id}"
}

resource "aws_codedeploy_deployment_group" "default" {
  count = "${var.alb_ssl_listener_arn == "" ? 1 : 0}"

  app_name               = "${aws_codedeploy_app.default.name}"
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  deployment_group_name  = "${module.codedeploy_group_label.id}"
  service_role_arn       =  "${module.ecs_bg_codepipeline.default_role_arn}"

  auto_rollback_configuration {
    enabled = true
    events = ["DEPLOYMENT_FAILURE"]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = "${var.ecs_cluster_name}"
    service_name = "${module.ecs_alb_service_task.service_name}"
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = ["${var.alb_http_listener_arn}"]
      }

      target_group {
        name = "${module.alb_ingress_blue.target_group_name}"
      }

      target_group {
        name = "${module.alb_ingress_green.target_group_name}"
      }

      test_traffic_route {
        listener_arns = ["${var.alb_test_listener_arn}"]
      }
    }
  }
}

resource "aws_codedeploy_deployment_group" "with_ssl" {
  count = "${var.alb_ssl_listener_arn == "" ? 0 : 1}"
  app_name               = "${aws_codedeploy_app.default.name}"
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  deployment_group_name  = "${module.codedeploy_group_label.id}"
  service_role_arn       = "${module.ecs_bg_codepipeline.default_role_arn}"

  trigger_configuration {
    trigger_events     = ["DeploymentSuccess", "DeploymentFailure", "DeploymentReady", "DeploymentFailure"]
    trigger_name       = "Update SSL Rule"
    trigger_target_arn = "${module.update_ssl_rule.this_sns_topic_arn}"
  }

  auto_rollback_configuration {
    enabled = true
    events = ["DEPLOYMENT_FAILURE"]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = "${var.ecs_cluster_name}"
    service_name = "${module.ecs_alb_service_task.service_name}"
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = ["${var.alb_http_listener_arn}"]
      }

      target_group {
        name = "${module.alb_ingress_blue.target_group_name}"
      }

      target_group {
        name = "${module.alb_ingress_green.target_group_name}"
      }

      test_traffic_route {
        listener_arns = ["${var.alb_test_listener_arn}"]
      }
    }
  }
}

module "ecs_bg_codepipeline" {
  enabled               = "${var.codepipeline_enabled}"
  source                = "git::https://github.com/GMADLA/terraform-aws-ecs-codepipeline.git?ref=tags/0.10.0"
  name                  = "${var.name}"
  namespace             = "${var.namespace}"
  stage                 = "${var.stage}"
  attributes            = "${var.attributes}"
  github_oauth_token    = "${var.github_oauth_token}"
  github_webhook_events = "${var.github_webhook_events}"
  repo_owner            = "${var.repo_owner}"
  repo_name             = "${var.repo_name}"
  branch                = "${var.branch}"
  badge_enabled         = "${var.badge_enabled}"
  build_image           = "${var.build_image}"
  build_timeout         = "${var.build_timeout}"
  buildspec             = "${var.buildspec}"
  image_repo_name       = "${module.ecr.repository_name}"
  service_name          = "${module.ecs_alb_service_task.service_name}"
  ecs_cluster_name      = "${var.ecs_cluster_name}"
  privileged_mode       = "true"
  poll_source_changes   = "${var.poll_source_changes}"

  pipeline_bucket_lifecycle_enabled = "true"

  webhook_enabled             = "${var.webhook_enabled}"
  webhook_target_action       = "${var.webhook_target_action}"
  webhook_authentication      = "${var.webhook_authentication}"
  webhook_filter_json_path    = "${var.webhook_filter_json_path}"
  webhook_filter_match_equals = "${var.webhook_filter_match_equals}"

  code_deploy_sns_topic_arn   = "${module.update_ssl_rule.this_sns_topic_arn}"
  code_deploy_lambda_hook_arns   = "${module.update_ssl_rule.update_ssl_lambda_function_arn}"

  code_deploy_application_name      = "${aws_codedeploy_app.default.name}"
  code_deploy_deployment_group_name = "${module.codedeploy_group_label.id}"

  environment_variables = [{
    "name"  = "CONTAINER_NAME"
    "value" = "${module.default_label.id}"
  }]
}


module "autoscaling" {
  enabled               = "${var.autoscaling_enabled}"
  source                = "git::https://github.com/cloudposse/terraform-aws-ecs-cloudwatch-autoscaling.git?ref=tags/0.1.0"
  name                  = "${var.name}"
  namespace             = "${var.namespace}"
  stage                 = "${var.stage}"
  attributes            = "${var.attributes}"
  service_name          = "${module.ecs_alb_service_task.service_name}"
  cluster_name          = "${var.ecs_cluster_name}"
  min_capacity          = "${var.autoscaling_min_capacity}"
  max_capacity          = "${var.autoscaling_max_capacity}"
  scale_down_adjustment = "${var.autoscaling_scale_down_adjustment}"
  scale_down_cooldown   = "${var.autoscaling_scale_down_cooldown}"
  scale_up_adjustment   = "${var.autoscaling_scale_up_adjustment}"
  scale_up_cooldown     = "${var.autoscaling_scale_up_cooldown}"
}

locals {
  cpu_utilization_high_alarm_actions    = "${var.autoscaling_enabled == "true" && var.autoscaling_dimension == "cpu" ? module.autoscaling.scale_up_policy_arn : ""}"
  cpu_utilization_low_alarm_actions     = "${var.autoscaling_enabled == "true" && var.autoscaling_dimension == "cpu" ? module.autoscaling.scale_down_policy_arn : ""}"
  memory_utilization_high_alarm_actions = "${var.autoscaling_enabled == "true" && var.autoscaling_dimension == "memory" ? module.autoscaling.scale_up_policy_arn : ""}"
  memory_utilization_low_alarm_actions  = "${var.autoscaling_enabled == "true" && var.autoscaling_dimension == "memory" ? module.autoscaling.scale_down_policy_arn : ""}"
}

module "ecs_alarms" {
  source     = "git::https://github.com/cloudposse/terraform-aws-ecs-cloudwatch-sns-alarms.git?ref=tags/0.4.0"
  name       = "${var.name}"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  attributes = "${var.attributes}"
  tags       = "${var.tags}"

  enabled      = "${var.ecs_alarms_enabled}"
  cluster_name = "${var.ecs_cluster_name}"
  service_name = "${module.ecs_alb_service_task.service_name}"

  cpu_utilization_high_threshold          = "${var.ecs_alarms_cpu_utilization_high_threshold}"
  cpu_utilization_high_evaluation_periods = "${var.ecs_alarms_cpu_utilization_high_evaluation_periods}"
  cpu_utilization_high_period             = "${var.ecs_alarms_cpu_utilization_high_period}"
  cpu_utilization_high_alarm_actions      = "${compact(concat(var.ecs_alarms_cpu_utilization_high_alarm_actions, list(local.cpu_utilization_high_alarm_actions)))}"
  cpu_utilization_high_ok_actions         = "${var.ecs_alarms_cpu_utilization_high_ok_actions}"

  cpu_utilization_low_threshold          = "${var.ecs_alarms_cpu_utilization_low_threshold}"
  cpu_utilization_low_evaluation_periods = "${var.ecs_alarms_cpu_utilization_low_evaluation_periods}"
  cpu_utilization_low_period             = "${var.ecs_alarms_cpu_utilization_low_period}"
  cpu_utilization_low_alarm_actions      = "${compact(concat(var.ecs_alarms_cpu_utilization_low_alarm_actions, list(local.cpu_utilization_low_alarm_actions)))}"
  cpu_utilization_low_ok_actions         = "${var.ecs_alarms_cpu_utilization_low_ok_actions}"

  memory_utilization_high_threshold          = "${var.ecs_alarms_memory_utilization_high_threshold}"
  memory_utilization_high_evaluation_periods = "${var.ecs_alarms_memory_utilization_high_evaluation_periods}"
  memory_utilization_high_period             = "${var.ecs_alarms_memory_utilization_high_period}"
  memory_utilization_high_alarm_actions      = "${compact(concat(var.ecs_alarms_memory_utilization_high_alarm_actions, list(local.memory_utilization_high_alarm_actions)))}"
  memory_utilization_high_ok_actions         = "${var.ecs_alarms_memory_utilization_high_ok_actions}"

  memory_utilization_low_threshold          = "${var.ecs_alarms_memory_utilization_low_threshold}"
  memory_utilization_low_evaluation_periods = "${var.ecs_alarms_memory_utilization_low_evaluation_periods}"
  memory_utilization_low_period             = "${var.ecs_alarms_memory_utilization_low_period}"
  memory_utilization_low_alarm_actions      = "${compact(concat(var.ecs_alarms_memory_utilization_low_alarm_actions, list(local.memory_utilization_low_alarm_actions)))}"
  memory_utilization_low_ok_actions         = "${var.ecs_alarms_memory_utilization_low_ok_actions}"
}

module "alb_blue_target_group_alarms" {
  enabled                        = "${var.alb_target_group_alarms_enabled}"
  source                         = "git::https://github.com/cloudposse/terraform-aws-alb-target-group-cloudwatch-sns-alarms.git?ref=tags/0.5.0"
  name                           = "${var.name}"
  namespace                      = "${var.namespace}"
  stage                          = "${var.stage}"
  attributes                     = ["${var.attributes}", "blue"]
  alarm_actions                  = ["${var.alb_target_group_alarms_alarm_actions}"]
  ok_actions                     = ["${var.alb_target_group_alarms_ok_actions}"]
  insufficient_data_actions      = ["${var.alb_target_group_alarms_insufficient_data_actions}"]
  alb_name                       = "${var.alb_name}"
  alb_arn_suffix                 = "${var.alb_arn_suffix}"
  target_group_name              = "${module.alb_ingress_blue.target_group_name}"
  target_group_arn_suffix        = "${module.alb_ingress_blue.target_group_arn_suffix}"
  target_3xx_count_threshold     = "${var.alb_target_group_alarms_3xx_threshold}"
  target_4xx_count_threshold     = "${var.alb_target_group_alarms_4xx_threshold}"
  target_5xx_count_threshold     = "${var.alb_target_group_alarms_5xx_threshold}"
  target_response_time_threshold = "${var.alb_target_group_alarms_response_time_threshold}"
  period                         = "${var.alb_target_group_alarms_period}"
  evaluation_periods             = "${var.alb_target_group_alarms_evaluation_periods}"
}

module "alb_green_target_group_alarms" {
  enabled                        = "${var.alb_target_group_alarms_enabled}"
  source                         = "git::https://github.com/cloudposse/terraform-aws-alb-target-group-cloudwatch-sns-alarms.git?ref=tags/0.5.0"
  name                           = "${var.name}"
  namespace                      = "${var.namespace}"
  stage                          = "${var.stage}"
  attributes                     = ["${var.attributes}", "green"]
  alarm_actions                  = ["${var.alb_target_group_alarms_alarm_actions}"]
  ok_actions                     = ["${var.alb_target_group_alarms_ok_actions}"]
  insufficient_data_actions      = ["${var.alb_target_group_alarms_insufficient_data_actions}"]
  alb_name                       = "${var.alb_name}"
  alb_arn_suffix                 = "${var.alb_arn_suffix}"
  target_group_name              = "${module.alb_ingress_green.target_group_name}"
  target_group_arn_suffix        = "${module.alb_ingress_green.target_group_arn_suffix}"
  target_3xx_count_threshold     = "${var.alb_target_group_alarms_3xx_threshold}"
  target_4xx_count_threshold     = "${var.alb_target_group_alarms_4xx_threshold}"
  target_5xx_count_threshold     = "${var.alb_target_group_alarms_5xx_threshold}"
  target_response_time_threshold = "${var.alb_target_group_alarms_response_time_threshold}"
  period                         = "${var.alb_target_group_alarms_period}"
  evaluation_periods             = "${var.alb_target_group_alarms_evaluation_periods}"
}
