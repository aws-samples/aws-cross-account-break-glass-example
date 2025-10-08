variable "AccoundID" {
  type        = string
  description = "Enter the AWS account ID where the BreakGlassUser is deployed"

  validation {
    condition     = length(var.AccoundID) == 12 && can(regex("^[[:digit:]]+$", var.AccoundID))
    error_message = "Account ID must be 12 digits"
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
          AWS = "arn:aws:iam::${var.AccoundID}:user/BreakglassUser"
        }
      },
    ]
  })
}

/* Assigning IAM Full Access to the breakglass user on the account where it's deployed
The code currently uses the AWS managed IAMFullAccess policy to ensure that the Breakglass User has sufficient permissions to be used in case of an emergency. 
This is NOT a least privileged policy and can be changed according to Organization's security requirements.
*/

resource "aws_iam_role_policy_attachment" "BreakGlassRole-test-role-policy-attach" {
  role       = aws_iam_role.BreakGlassRole.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}
