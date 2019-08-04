locals {
  ssl_enabled = "${var.alb_ssl_listener_arn == "" ? false : true}"
}

module "update_ssl_rule" {
  source         = "./sns_lambda_update_ssl_rule"
  create         = "${local.ssl_enabled}"
  name           = "${var.name}"
  namespace      = "${var.namespace}"
  stage          = "${var.stage}"
  attributes     = "${var.attributes}"
  aws_region     = "${var.aws_logs_region}"

  ecs_cluster_name  = "${var.ecs_cluster_name}"
  http_listener_arn = "${var.alb_http_listener_arn}"
  ssl_listener_arn  = "${var.alb_ssl_listener_arn}"
  available_target_groups = ["${module.alb_ingress_blue.target_group_arn}","${module.alb_ingress_green.target_group_arn}"]

  codedeploy_app_name       = "${aws_codedeploy_app.default.name}"
  codedeploy_group_name     = "${element(concat(aws_codedeploy_deployment_group.with_ssl.*.deployment_group_name, list("")), 0)}"
}
