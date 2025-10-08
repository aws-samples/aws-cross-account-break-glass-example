data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id        = data.aws_caller_identity.current.account_id
  current_region    = data.aws_region.current.id
  is_primary_region = var.primary_region == "" || var.primary_region == local.current_region
  target_account_id = var.primary_account_id != "" ? var.primary_account_id : local.account_id
  target_region     = var.primary_region != "" ? var.primary_region : local.current_region
}

variable "emailAddress" {
  type        = string
  description = "Enter the email address to subscribe to the SNS notification"
}

variable "monitoring_regions" {
  type        = list(string)
  description = "List of AWS regions to monitor for ConsoleLogin events"
  default = [
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "eu-north-1", "eu-central-1", "eu-west-1", "eu-west-2", "eu-west-3", "eu-south-1", "eu-south-2", "eu-central-2",
    "ap-southeast-2", "ap-southeast-1", "ap-northeast-1", "ap-northeast-2", "ap-northeast-3",
    "ap-south-1", "ap-south-2", "ap-southeast-3", "ap-southeast-4", "ap-southeast-5", "ap-southeast-7",
    "ap-east-1", "ap-east-2",
    "ca-central-1", "ca-west-1",
    "sa-east-1",
    "af-south-1",
    "me-south-1", "me-central-1",
    "il-central-1",
    "mx-central-1"
  ]
}

variable "primary_region" {
  type        = string
  description = "Primary region where SNS topic is located (for cross-region forwarding)"
  default     = ""
}

variable "primary_account_id" {
  type        = string
  description = "Account ID where primary SNS topic is located (for cross-region forwarding)"
  default     = ""
}

// Break Glass User - Created only in primary region for centralized control
resource "aws_iam_user" "bguser" {
  count = local.is_primary_region ? 1 : 0
  name  = "BreakglassUser"
}
/*
 * Emergency Access Permissions
 * 
 * WARNING: Uses IAMFullAccess for emergency scenarios - NOT least privilege
 * This ensures the Break Glass User can manage IAM resources during emergencies
 * when normal access methods fail.
 * 
 * Security Considerations:
 * - Customize permissions based on organizational requirements
 * - Consider implementing time-based access controls
 * - Regular security reviews and audits are essential
 */
resource "aws_iam_user_policy_attachment" "IAMAccess" {
  count      = local.is_primary_region ? 1 : 0
  user       = aws_iam_user.bguser[0].name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}
// Cross-account role assumption policy - allows Break Glass User to assume BreakGlassRole in any account

resource "aws_iam_policy" "BreakGlassAssumeRole" {
  count       = local.is_primary_region ? 1 : 0
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
  count      = local.is_primary_region ? 1 : 0
  user       = aws_iam_user.bguser[0].name
  policy_arn = aws_iam_policy.BreakGlassAssumeRole[0].arn
}

// Console Login monitoring - deployed across all regions where ConsoleLogin events can occur
resource "aws_cloudwatch_event_rule" "login_event" {
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

resource "aws_cloudwatch_event_target" "login_target" {
  rule      = aws_cloudwatch_event_rule.login_event.name
  target_id = local.is_primary_region ? "SendToSNS" : "SendToDefaultEventBus"
  arn       = local.is_primary_region ? aws_sns_topic.aws_logins[0].arn : "arn:aws:events:${local.target_region}:${local.target_account_id}:event-bus/default"
  role_arn  = local.is_primary_region ? null : "arn:aws:iam::${local.account_id}:role/breakglass-event-bus-role"
}

// SwitchRole monitoring - captures role switching activities in the AWS Console
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
  target_id = local.is_primary_region ? "SendToSNS" : "SendToDefaultEventBus"
  arn       = local.is_primary_region ? aws_sns_topic.aws_logins[0].arn : "arn:aws:events:${local.target_region}:${local.target_account_id}:event-bus/default"
  role_arn  = local.is_primary_region ? null : "arn:aws:iam::${local.account_id}:role/breakglass-event-bus-role"
}

// AssumeRole monitoring - captures CLI/API-based role assumptions
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
  target_id = local.is_primary_region ? "SendToSNS" : "SendToDefaultEventBus"
  arn       = local.is_primary_region ? aws_sns_topic.aws_logins[0].arn : "arn:aws:events:${local.target_region}:${local.target_account_id}:event-bus/default"
  role_arn  = local.is_primary_region ? null : "arn:aws:iam::${local.account_id}:role/breakglass-event-bus-role"
}

// Centralized SNS topic - created only in primary region for unified alerting
resource "aws_sns_topic" "aws_logins" {
  count             = local.is_primary_region ? 1 : 0
  name              = "breakglassuser-console-logins"
  kms_master_key_id = "alias/breakglassSNS"
}

resource "aws_sns_topic_subscription" "sns-topic" {
  count     = local.is_primary_region ? 1 : 0
  topic_arn = aws_sns_topic.aws_logins[0].arn
  protocol  = "email"
  endpoint  = var.emailAddress
}

resource "aws_sns_topic_policy" "default" {
  count  = local.is_primary_region ? 1 : 0
  arn    = aws_sns_topic.aws_logins[0].arn
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

    resources = local.is_primary_region ? [aws_sns_topic.aws_logins[0].arn] : []
  }
}

/*
 * Customer-Managed KMS Key for SNS Encryption
 * 
 * Required because:
 * - Default AWS KMS key (alias/aws/sns) doesn't allow EventBridge to publish
 * - AWS-managed keys cannot be modified to grant EventBridge permissions
 * - Customer-managed keys provide full control over access policies
 * 
 */

resource "aws_kms_key" "kmskey" {
  count                   = local.is_primary_region ? 1 : 0
  description             = "BreakGlass SNS Topic"
  deletion_window_in_days = 10
  policy                  = data.aws_iam_policy_document.keypolicy.json
  enable_key_rotation     = true
}
resource "aws_kms_alias" "alias" {
  count         = local.is_primary_region ? 1 : 0
  name          = "alias/breakglassSNS"
  target_key_id = aws_kms_key.kmskey[0].key_id
}

// KMS Key Policy - grants EventBridge publish permissions and account root access for key management
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

// Cross-region event forwarding role - allows secondary regions to forward events to primary region
resource "aws_iam_role" "event_bus_role" {
  count = local.is_primary_region ? 1 : 0
  name  = "breakglass-event-bus-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "event_bus_policy" {
  count = local.is_primary_region ? 1 : 0
  name  = "breakglass-event-bus-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "events:PutEvents"
        Resource = "arn:aws:events:*:${local.account_id}:event-bus/default"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "event_bus_attachment" {
  count      = local.is_primary_region ? 1 : 0
  role       = aws_iam_role.event_bus_role[0].name
  policy_arn = aws_iam_policy.event_bus_policy[0].arn
}


