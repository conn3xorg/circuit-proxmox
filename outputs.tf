output "web_urls" {
  description = "Address of each node's web interface, by host name."
  value       = { for name, ip in local.node_ip : name => "https://${ip}:8006" }
}
