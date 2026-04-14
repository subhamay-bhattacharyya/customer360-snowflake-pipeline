# Temporary debug outputs — DELETE BEFORE MERGING TO MAIN
output "debug_private_key_sha256" {
  description = "SHA256 hash of the reconstructed PEM to verify key integrity in HCP"
  value       = sha256("-----BEGIN PRIVATE KEY-----\n${join("\n", regexall(".{1,64}", trimspace(var.snowflake_private_key)))}\n-----END PRIVATE KEY-----")
}

output "debug_private_key_length" {
  description = "Length of the raw key body received from HCP"
  value       = length(trimspace(var.snowflake_private_key))
}

output "debug_private_key_first8" {
  description = "First 8 chars of key body to verify no corruption"
  value       = substr(trimspace(var.snowflake_private_key), 0, 8)
}

output "debug_private_key_last8" {
  description = "Last 8 chars of key body to verify no truncation"
  value       = substr(trimspace(var.snowflake_private_key), length(trimspace(var.snowflake_private_key)) - 8, 8)
}
