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

module "alb_ingress_prod" {
  count            = "${var.blue_green_enabled == "true" ? 1 : 0}"
  source            = "git::https://github.com/cloudposse/terraform-aws-alb-ingress.git?ref=tags/0.7.0"
  name              = "${var.name}"
  namespace         = "${var.namespace}"
  stage             = "${var.stage}"
  attributes        = ["${var.attributes}", "prod"]
  vpc_id            = "${var.vpc_id}"
  port              = "${var.container_port}"
  health_check_path = "${var.alb_ingress_healthcheck_path}"

  unauthenticated_paths = ["${var.alb_ingress_unauthenticated_paths}"]
  unauthenticated_hosts = ["${var.alb_ingress_unauthenticated_hosts}"]

  unauthenticated_priority = "${var.alb_ingress_listener_unauthenticated_priority}"

  unauthenticated_listener_arns       = ["${var.alb_prod_listener_arn}", "${var.alb_ssl_listener_arn}"]
  unauthenticated_listener_arns_count = "${var.alb_ingress_prod_listener_arns_count}"
}

module "alb_ingress_test" {
  count            = "${var.blue_green_enabled == "false" ? 1 : 0}"
  source            = "git::https://github.com/cloudposse/terraform-aws-alb-ingress.git?ref=tags/0.7.0"
  name              = "${var.name}"
  namespace         = "${var.namespace}"
  stage             = "${var.stage}"
  attributes        = ["${var.attributes}", "test"]
  vpc_id            = "${var.vpc_id}"
  port              = "${var.container_port}"
  health_check_path = "${var.alb_ingress_healthcheck_path}"

  unauthenticated_paths = ["${var.alb_ingress_unauthenticated_paths}"]
  unauthenticated_hosts = ["${var.alb_ingress_unauthenticated_hosts}"]

  unauthenticated_priority = "${var.alb_ingress_listener_unauthenticated_priority}"

  unauthenticated_listener_arns       = ["${var.alb_test_listener_arn}"]
  unauthenticated_listener_arns_count = "1"
}

module "alb_blue_target_group_alarms" {
  count                          = "${var.blue_green_enabled == "true" ? 1 : 0}"
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
  target_group_name              = "${module.alb_ingress_prod.target_group_name}"
  target_group_arn_suffix        = "${module.alb_ingress_prod.target_group_arn_suffix}"
  target_3xx_count_threshold     = "${var.alb_target_group_alarms_3xx_threshold}"
  target_4xx_count_threshold     = "${var.alb_target_group_alarms_4xx_threshold}"
  target_5xx_count_threshold     = "${var.alb_target_group_alarms_5xx_threshold}"
  target_response_time_threshold = "${var.alb_target_group_alarms_response_time_threshold}"
  period                         = "${var.alb_target_group_alarms_period}"
  evaluation_periods             = "${var.alb_target_group_alarms_evaluation_periods}"
}

module "alb_green_target_group_alarms" {
  count                          = "${var.blue_green_enabled == "true" ? 1 : 0}"
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
  target_group_name              = "${module.alb_ingress_test.target_group_name}"
  target_group_arn_suffix        = "${module.alb_ingress_test.target_group_arn_suffix}"
  target_3xx_count_threshold     = "${var.alb_target_group_alarms_3xx_threshold}"
  target_4xx_count_threshold     = "${var.alb_target_group_alarms_4xx_threshold}"
  target_5xx_count_threshold     = "${var.alb_target_group_alarms_5xx_threshold}"
  target_response_time_threshold = "${var.alb_target_group_alarms_response_time_threshold}"
  period                         = "${var.alb_target_group_alarms_period}"
  evaluation_periods             = "${var.alb_target_group_alarms_evaluation_periods}"
}


# BLUE/GREEN ✖‿✖
resource "aws_codedeploy_app" "default" {
  count            = "${var.blue_green_enabled == "false" ? 0 : 1}"
  compute_platform = "ECS"
  name             = "${module.codedeploy_label.id}"
}

resource "aws_codedeploy_deployment_group" "default" {
  count                  = "${var.blue_green_enabled == "false" ? 0 : 1}"
  app_name               = "${aws_codedeploy_app.default.name}"
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  deployment_group_name  = "${module.codedeploy_group_label.id}"
  service_role_arn       =  "${module.ecs_alb_service_task.service_role_arn}"

  auto_rollback_configuration {
    enable = true
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
        listener_arns = ["${var.alb_prod_listener_arn}"]
      }

      target_group {
        name = "${var.alb_target_group_blue_arn}"
      }

      target_group {
        name = "${var.alb_target_group_green_arn}"
      }

      test_traffic_route {
        listener_arns = ["${var.alb_test_listener_arn}"]
      }
    }
  }
}

module "ecs_bg_codepipeline" {
  count                 = "${var.blue_green_enabled == "true" ? 1 : 0}"
  enabled               = "${var.codepipeline_enabled}"
  source                = "git::https://github.com/GMADLA/terraform-aws-ecs-codepipeline.git?ref=tags/0.10.0-dev.2"
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

  webhook_enabled             = "${var.webhook_enabled}"
  webhook_target_action       = "${var.webhook_target_action}"
  webhook_authentication      = "${var.webhook_authentication}"
  webhook_filter_json_path    = "${var.webhook_filter_json_path}"
  webhook_filter_match_equals = "${var.webhook_filter_match_equals}"

  blue_green_enabled                = true
  code_deploy_application_name      = "${aws_codedeploy_deployment_group.default.app_name}"
  code_deploy_deployment_group_name = "${aws_codedeploy_deployment_group.default.deployment_group_name}"

  environment_variables = [{
    "name"  = "CONTAINER_NAME"
    "value" = "${module.default_label.id}"
  }]
}
