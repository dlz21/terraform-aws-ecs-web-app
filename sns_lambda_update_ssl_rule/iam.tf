locals {
  lambda_name = "${var.lambda_function_name == "" ? module.lambda_label.id: var.lambda_function_name}"
}

module "default_label" {
  source    = "git::https://github.com/cloudposse/terraform-terraform-label.git?ref=tags/0.1.3"
  name      = "${var.name}"
  namespace = "${var.namespace}"
  stage     = "${var.stage}"
}

data "aws_iam_policy_document" "assume_role" {
  count = "${var.create ? 1 : 0}"

  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_basic" {
  count = "${var.create ? 1 : 0}"

  statement {
    sid = "AllowWriteLogGroup"

    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    sid = "AllowWritetoLogGroup"

    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${format("arn:aws:logs:%s:*:log-group:/aws/lambda/%s:*", var.aws_region, local.lambda_name)}"]
  }

  statement {
    sid = "AllowDescribeTargetGroups"

    effect = "Allow"

    actions = [
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeRules"
    ]

    resources = ["*"]
  }

  statement {
    sid = "AllowModifyListener"

    effect = "Allow"

    actions = [
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyRule",
    ]

    resources = [
      "${var.ssl_listener_arn}",
      "${format("arn:aws:elasticloadbalancing:%s:*:listener-rule/app/%s-%s*/*/*/*", var.aws_region, var.namespace, var.stage)}"
    ]
  }

  statement {
      sid = "AllowPutLifeCycleHook"

      effect = "Allow"

      actions = [
        "codedeploy:PutLifecycleEventHookExecutionStatus"
      ]

      resources = [
        "${format("arn:aws:codedeploy:%s:*:deploymentgroup:%s/%s", var.aws_region, var.codedeploy_app_name, var.codedeploy_group_name)}"
      ]
  }
}

data "aws_iam_policy_document" "lambda" {
  count = "${(var.create_with_kms_key == 1 ? 1 : 0) * (var.create ? 1 : 0)}"

  source_json = "${data.aws_iam_policy_document.lambda_basic.0.json}"

  statement {
    sid = "AllowKMSDecrypt"

    effect = "Allow"

    actions = ["kms:Decrypt"]

    resources = ["${var.kms_key_arn == "" ? "" : var.kms_key_arn}"]
  }
}

resource "aws_iam_role" "lambda" {
  count = "${var.create ? 1 : 0}"

  name_prefix        = "lambda"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role.0.json}"
}

resource "aws_iam_role_policy" "lambda" {
  count = "${var.create ? 1 : 0}"

  name_prefix = "lambda-policy-"
  role        = "${aws_iam_role.lambda.0.id}"

  policy = "${element(compact(concat(data.aws_iam_policy_document.lambda.*.json, data.aws_iam_policy_document.lambda_basic.*.json)), 0)}"
}
