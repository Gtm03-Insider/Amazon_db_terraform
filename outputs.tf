// Output: EC2 instance identifier
output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.mssql.id
}

// Output: Public IP address to connect to the instance
output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.mssql.public_ip
}
output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.mssql.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.mssql.public_ip
}
