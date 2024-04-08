data "aws_caller_identity" "current" {}
locals {
  account_id = data.aws_caller_identity.current.account_id
}

variable "emailAddress" {
  type        = string
  description = "Enter the email address to subscribe to the SNS notification"
}

//Creates a Breakglass User
resource "aws_iam_user" "bguser" {
  name = "BreakglassUser"
}
/* Assigning IAM Full Access to the breakglass user on the account where it's deployed
The code currently uses the AWS managed IAMFullAccess policy to ensure that the Breakglass User has sufficient permissions to be used in case of an emergency. 
This is NOT a least privileged policy and can be changed according to Organization's security requirements.
*/
resource "aws_iam_user_policy_attachment" "IAMAccess" {
  user       = aws_iam_user.bguser.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}
// Policy which allows the IAM User to perform a switch role to the BreakGlassRole

resource "aws_iam_policy" "BreakGlassAssumeRole" {
  name        = "BreakGlassAssumeRole"
  description = "BreakGlassAssumeRole"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "sts:AssumeRole"
        Effect   = "Allow"
        Resource = "arn:aws:iam::*:role/BreakGlassRole"
      },
    ]
  })
}
resource "aws_iam_user_policy_attachment" "assume-role" {
  user       = aws_iam_user.bguser.name
  policy_arn = aws_iam_policy.BreakGlassAssumeRole.arn
}

// Cloudwatch Alarm for breakglass user login

resource "aws_cloudwatch_event_rule" "login-event" {
  name        = "capture-breakglass-user-sign-in"
  description = "Capture breakglass user AWS Console Sign In"

  event_pattern = <<EOF
{
  "detail-type": ["AWS Console Sign In via CloudTrail"],
  "source": ["aws.signin"],
  "detail": {
    "eventSource": ["signin.amazonaws.com"],
    "eventName": ["ConsoleLogin"],
    "userIdentity": {
      "type": ["IAMUser"],
      "userName": ["BreakglassUser"]
    }
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "login-target" {
  rule      = aws_cloudwatch_event_rule.login-event.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.aws_logins.arn
}

// Cloudwatch Alarm for breakglass user switch role

resource "aws_cloudwatch_event_rule" "switch-event" {
  name        = "capture-breakglass-user-switch-role"
  description = "Capture breakglass user switching roles"

  event_pattern = <<EOF
{
  "source": ["aws.signin"],
  "detail-type": ["AWS Console Sign In via CloudTrail"],
  "detail": {
    "eventSource": ["signin.amazonaws.com"],
    "eventName": ["SwitchRole"],
    "userIdentity": {
      "type": ["IAMUser"],
      "userName": ["BreakglassUser"]
    }
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "switch-target" {
  rule      = aws_cloudwatch_event_rule.switch-event.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.aws_logins.arn
}

resource "aws_cloudwatch_event_target" "login-target" {
  rule      = aws_cloudwatch_event_rule.login-event.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.aws_logins.arn
}

// Cloudwatch Alarm for breakglass user assume role

resource "aws_cloudwatch_event_rule" "assume-event" {
  name        = "capture-breakglass-user-assume-role"
  description = "Capture breakglass user assuming roles via the CLI"

  event_pattern = <<EOF
{
  "source": ["aws.sts"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["sts.amazonaws.com"],
    "eventName": ["AssumeRole"],
    "userIdentity": {
      "type": ["IAMUser"],
      "userName": ["BreakglassUser"]
    }
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "assume-target" {
  rule      = aws_cloudwatch_event_rule.assume-event.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.aws_logins.arn
}

//SNS topic creation
resource "aws_sns_topic" "aws_logins" {
  name              = "breakglassuser-console-logins"
  kms_master_key_id = "alias/breakglassSNS"
}

resource "aws_sns_topic_subscription" "sns-topic" {
  topic_arn = aws_sns_topic.aws_logins.arn
  protocol  = "email"
  endpoint  = var.emailAddress
}

resource "aws_sns_topic_policy" "default" {
  arn    = aws_sns_topic.aws_logins.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    effect  = "Allow"
    actions = ["SNS:Publish"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [aws_sns_topic.aws_logins.arn]
  }
}

/* Optional Customer CMK
SNS allows encryption at rest for its topic. If SNS uses the default AWS Key Management Service (AWS KMS) key alias/aws/sns for this encryption, then CloudWatch alarms can't publish messages to the SNS topic. 
The default AWS KMS key's policy for SNS doesn't allow CloudWatch alarms to perform kms:Decrypt and kms:GenerateDataKey API calls. Because this key is AWS managed, you can't manually edit the policy.
If the SNS topic must be encrypted at rest, then use a customer managed key. 
*/

resource "aws_kms_key" "kmskey" {
  description             = "BreakGlass SNS Topic"
  deletion_window_in_days = 10
  policy                  = data.aws_iam_policy_document.keypolicy.json
  enable_key_rotation     = true
}
resource "aws_kms_alias" "alias" {
  name          = "alias/breakglassSNS"
  target_key_id = aws_kms_key.kmskey.key_id
}

// The key policy can be different based on your organizational standards. Below policy here provides full access to the key by the 'ROOT' user whose usage is strongly discouraged.
data "aws_iam_policy_document" "keypolicy" {
  statement {
    sid       = "allow_events_to_decrypt_key"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
    ]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }

  statement {
    sid       = "Enable IAM User Permissions"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["kms:*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}
