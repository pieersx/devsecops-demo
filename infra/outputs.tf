output "instance_ids" {
  description = "ID de cada VPS (para abrir sesiones SSM)."
  value       = { for k, v in aws_instance.vm : k => v.id }
}

output "gateway_public_ip" {
  value = aws_instance.vm["gateway"].public_ip
}

output "ansible_ssm_bucket" {
  description = "Exportar como ANSIBLE_SSM_BUCKET antes de ejecutar Ansible."
  value       = aws_s3_bucket.ansible.bucket
}

output "github_deploy_role_arn" {
  description = "Guardar como variable de GitHub Actions AWS_ROLE_ARN."
  value       = try(aws_iam_role.github_deploy[0].arn, null)
}
