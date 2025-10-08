variable "AccountID" {
  type        = string
  description = "AWS account ID where the Break Glass User is deployed"

  validation {
    condition     = length(var.AccountID) == 12 && can(regex("^[[:digit:]]+$", var.AccountID))
    error_message = "Account ID must be exactly 12 digits"
  }
}

resource "aws_iam_role" "BreakGlassRole" {
  name = "BreakGlassRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = "arn:aws:iam::${var.AccountID}:user/BreakglassUser"
        }
      },
    ]
  })
}

/*
 * Emergency Access Permissions
 * 
 * WARNING: This role uses IAMFullAccess which grants extensive privileges.
 * This is intentional for emergency scenarios but is NOT least privilege.
 * 
 * Customize this policy based on your organization's security requirements:
 * - Consider using custom policies with specific permissions
 * - Implement time-based access controls if needed
 * - Review and audit permissions regularly
 */

resource "aws_iam_role_policy_attachment" "BreakGlassRole-policy-attachment" {
  role       = aws_iam_role.BreakGlassRole.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}
