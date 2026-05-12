output "summary" {
  description = "Total objects created per category"
  value = {
    keypairs           = length(sws_keypair.admin) + length(sws_keypair.ops)
    networks           = 2
    subnets            = length(sws_subnet.tiers)
    routers            = 1
    router_interfaces  = length(sws_router_interface.tiers)
    floating_ips       = length(sws_floating_ip.edge)
    peerings           = 1
    security_groups    = length(sws_security_group.tiers)
    security_rules     = length(sws_security_group.tiers) * 2 + 6    # 2 common + 6 tier-specific
    instances          = length(sws_instance.workloads)
    volumes            = length(sws_volume.data)
    volume_attachments = length(sws_volume_attachment.data)
    volume_snapshots   = length(sws_volume_snapshot.baseline)
    buckets            = length(sws_object_bucket.buckets)
    databases          = 2
    load_balancers     = 2
    lb_listeners       = 3
    lb_pools           = 2
    lb_members         = length(sws_lb_member.web) + length(sws_lb_member.app)
    lb_health_monitors = 2
    dns_zones          = 1
    dns_records        = 5
    private_dns_zones  = 1
    cache              = 1
    queue              = 1
    kafka              = 1
    file_storage       = 1
    bastion            = 1
    logging            = 1
    cdn                = 1
    notification       = 1
    pipeline           = 1
    registry           = 1
    backup_policy      = 1
    serverless         = 1
    vault_secret       = 1
    alarm              = 1
    tag                = 1
    kubernetes_cluster = var.enable_kubernetes ? 1 : 0
  }
}

output "network_id"        { value = sws_network.spoke.id }
output "subnet_ids"        { value = { for k, v in sws_subnet.tiers : k => v.id } }
output "instance_ids"      { value = { for k, v in sws_instance.workloads : k => v.id } }
output "instance_ips"      { value = { for k, v in sws_instance.workloads : k => v.ip_address } }
output "floating_ips"      { value = [for f in sws_floating_ip.edge : f.address] }
output "lb_public_id"      { value = sws_load_balancer.public.id }
output "lb_internal_id"    { value = sws_load_balancer.internal.id }
output "postgres_id"       { value = sws_managed_database.postgres.id }
output "mysql_id"          { value = sws_managed_database.mysql.id }
output "bucket_names"      { value = [for b in sws_object_bucket.buckets : b.name] }
output "dns_zone_id"       { value = sws_dns_zone.public.id }
output "bastion_id"        { value = sws_bastion.jump.id }
output "k8s_cluster_id"    { value = var.enable_kubernetes ? sws_kubernetes_cluster.demo[0].id : null }
