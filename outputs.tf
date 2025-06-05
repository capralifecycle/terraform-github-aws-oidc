output "admin_role" {
  description = "The IAM Role used for trunk branch deployments, providing full access to the remote resources."
  value = {
    name = aws_iam_role.admin.name
  }
}

output "reader_role" {
  description = "The IAM Role used for non-trunk branch deployments, providing read access to the remote resources."
  value = {
    name = aws_iam_role.read.name
  }
}
