###############################################################################
#  spoke-test — every typed savannaacloud/sws resource × scale = 100+ objects
#
#  Single spoke (10.50.0.0/16) carries multiple subnets, three app tiers
#  (web / app / worker), block + object + file storage, two managed DBs, two
#  LBs, public + private DNS, and every Tier-3 service the provider exposes.
#
#  Default scale (tier_workload_count = 3) creates ~110 Savannaa objects.
#  Knock the variable down to 1 for a fast smoke test, up to 5+ for a full
#  load test.
###############################################################################

locals {
  prefix = "spoke-test"

  # Three subnets for east-west isolation. Each app tier lives on one.
  subnets = {
    web    = { cidr = "10.50.1.0/24", gw = "10.50.1.1" }
    app    = { cidr = "10.50.2.0/24", gw = "10.50.2.1" }
    worker = { cidr = "10.50.3.0/24", gw = "10.50.3.1" }
  }
}

# ── 1. Identity & access ──────────────────────────────────────────────────
resource "sws_keypair" "admin" {
  count      = var.ssh_public_key == "" ? 0 : 1
  name       = "${local.prefix}-admin"
  public_key = var.ssh_public_key
}

# Two SSH-key personas to demonstrate the multi-keypair pattern.
resource "sws_keypair" "ops" {
  count      = var.ssh_public_key == "" ? 0 : 1
  name       = "${local.prefix}-ops"
  public_key = var.ssh_public_key   # in real use, pass a separate var
}

# ── 2. Networking ─────────────────────────────────────────────────────────
resource "sws_network" "spoke" {
  name = "${local.prefix}-spoke"
  cidr = "10.50.0.0/16"
}

# A second network for peering demo.
resource "sws_network" "transit" {
  name = "${local.prefix}-transit"
  cidr = "10.51.0.0/16"
}

resource "sws_subnet" "tiers" {
  for_each = local.subnets

  name            = "${local.prefix}-${each.key}-subnet"
  network_id      = sws_network.spoke.id
  cidr            = each.value.cidr
  gateway_ip      = each.value.gw
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
}

resource "sws_router" "spoke" {
  name = "${local.prefix}-router"
}

resource "sws_router_interface" "tiers" {
  for_each = sws_subnet.tiers

  router_id = sws_router.spoke.id
  subnet_id = each.value.id
}

resource "sws_floating_ip" "edge" {
  count       = 5
  description = "${local.prefix} edge IP #${count.index + 1}"
}

resource "sws_vpc_peering" "spoke_to_transit" {
  name = "${local.prefix}-spoke-to-transit"
  config = jsonencode({
    local_network_id = sws_network.spoke.id
    peer_network_id  = sws_network.transit.id
  })
}

# ── 3. Security ───────────────────────────────────────────────────────────
resource "sws_security_group" "tiers" {
  for_each    = toset(["web", "app", "worker", "db", "lb"])
  name        = "${local.prefix}-sg-${each.value}"
  description = "${each.value} tier"
}

# Common rules (SSH from anywhere, ICMP). Real prod tightens CIDRs.
resource "sws_security_group_rule" "ssh" {
  for_each = sws_security_group.tiers

  security_group_id = each.value.id
  direction         = "ingress"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "sws_security_group_rule" "icmp" {
  for_each = sws_security_group.tiers

  security_group_id = each.value.id
  direction         = "ingress"
  protocol          = "icmp"
  remote_ip_prefix  = "10.50.0.0/16"
}

# Web tier exposes 80/443; app tier exposes 8080; db tier exposes 5432/3306.
resource "sws_security_group_rule" "web_http" {
  security_group_id = sws_security_group.tiers["web"].id
  direction = "ingress"
  protocol = "tcp"
  port_range_min = 80
  port_range_max = 80
  remote_ip_prefix = "0.0.0.0/0"
}
resource "sws_security_group_rule" "web_https" {
  security_group_id = sws_security_group.tiers["web"].id
  direction = "ingress"
  protocol = "tcp"
  port_range_min = 443
  port_range_max = 443
  remote_ip_prefix = "0.0.0.0/0"
}
resource "sws_security_group_rule" "app_api" {
  security_group_id = sws_security_group.tiers["app"].id
  direction = "ingress"
  protocol = "tcp"
  port_range_min = 8080
  port_range_max = 8080
  remote_ip_prefix = "10.50.1.0/24"
}
resource "sws_security_group_rule" "db_pg" {
  security_group_id = sws_security_group.tiers["db"].id
  direction = "ingress"
  protocol = "tcp"
  port_range_min = 5432
  port_range_max = 5432
  remote_ip_prefix = "10.50.0.0/16"
}
resource "sws_security_group_rule" "db_mysql" {
  security_group_id = sws_security_group.tiers["db"].id
  direction = "ingress"
  protocol = "tcp"
  port_range_min = 3306
  port_range_max = 3306
  remote_ip_prefix = "10.50.0.0/16"
}
resource "sws_security_group_rule" "lb_health" {
  security_group_id = sws_security_group.tiers["lb"].id
  direction = "ingress"
  protocol = "tcp"
  port_range_min = 80
  port_range_max = 80
  remote_ip_prefix = "0.0.0.0/0"
}

# ── 4. Compute — 3 tiers × N instances ────────────────────────────────────
data "sws_image" "ubuntu" { name = "Ubuntu 22.04 LTS" }
data "sws_plan"  "small"  { name = "m1.small" }
data "sws_plan"  "medium" { name = "m1.medium" }

locals {
  workloads = flatten([
    for tier in ["web", "app", "worker"] : [
      for i in range(var.tier_workload_count) : {
        tier  = tier
        index = i
        key   = "${tier}-${i + 1}"
      }
    ]
  ])
}

resource "sws_instance" "workloads" {
  for_each = { for w in local.workloads : w.key => w }

  name       = "${local.prefix}-${each.value.key}"
  plan       = each.value.tier == "worker" ? data.sws_plan.medium.name : data.sws_plan.small.name
  image      = data.sws_image.ubuntu.id
  network_id = sws_network.spoke.id
  keypair    = length(sws_keypair.admin) > 0 ? sws_keypair.admin[0].name : null
  public_ip  = each.value.tier == "web" && each.value.index == 0   # only web-1 gets a public IP
}

# ── 5. Block storage — 1 volume per workload ──────────────────────────────
resource "sws_volume" "data" {
  for_each = sws_instance.workloads
  name     = "${each.value.name}-data"
  size     = 20
}

resource "sws_volume_attachment" "data" {
  for_each    = sws_volume.data
  volume_id   = each.value.id
  instance_id = sws_instance.workloads[each.key].id
  device      = "/dev/vdb"
}

resource "sws_volume_snapshot" "baseline" {
  for_each = sws_volume.data
  volume_id = each.value.id
  name     = "${each.value.name}-baseline"
  depends_on = [sws_volume_attachment.data]
}

# ── 6. Object storage — 3 buckets per common use case ────────────────────
resource "sws_object_bucket" "buckets" {
  for_each = toset(["assets", "logs", "backups"])
  name     = "${local.prefix}-${each.value}"
}

# ── 7. Managed databases — 1 postgres + 1 mysql ──────────────────────────
resource "sws_managed_database" "postgres" {
  name       = "${local.prefix}-pg"
  datastore  = "postgresql"
  version    = "16"
  flavor_id  = "r1.medium"
  size       = 20
  network_id = sws_network.spoke.id
}

resource "sws_managed_database" "mysql" {
  name       = "${local.prefix}-mysql"
  datastore  = "mysql"
  version    = "8.4"
  flavor_id  = "r1.medium"
  size       = 20
  network_id = sws_network.spoke.id
}

# ── 8. Load balancer — 2 LBs (public + internal) ─────────────────────────
resource "sws_load_balancer" "public" {
  name          = "${local.prefix}-lb-public"
  vip_subnet_id = sws_subnet.tiers["web"].id
  description   = "Public HTTP LB fronting the web tier"
}

resource "sws_load_balancer" "internal" {
  name          = "${local.prefix}-lb-internal"
  vip_subnet_id = sws_subnet.tiers["app"].id
  description   = "Internal LB fronting the app tier"
}

resource "sws_lb_listener" "public_http" {
  load_balancer_id = sws_load_balancer.public.id
  name = "${local.prefix}-listener-80"
  protocol = "HTTP"
  protocol_port = 80
}
resource "sws_lb_listener" "public_https" {
  load_balancer_id = sws_load_balancer.public.id
  name = "${local.prefix}-listener-443"
  protocol = "HTTPS"
  protocol_port = 443
}
resource "sws_lb_listener" "internal_api" {
  load_balancer_id = sws_load_balancer.internal.id
  name = "${local.prefix}-listener-8080"
  protocol = "HTTP"
  protocol_port = 8080
}

resource "sws_lb_pool" "web" {
  load_balancer_id = sws_load_balancer.public.id
  name = "${local.prefix}-pool-web"
  protocol = "HTTP"
  lb_algorithm = "ROUND_ROBIN"
}
resource "sws_lb_pool" "app" {
  load_balancer_id = sws_load_balancer.internal.id
  name = "${local.prefix}-pool-app"
  protocol = "HTTP"
  lb_algorithm = "LEAST_CONNECTIONS"
}

resource "sws_lb_member" "web" {
  for_each       = { for k, v in sws_instance.workloads : k => v if startswith(k, "web-") }
  pool_id        = sws_lb_pool.web.id
  address        = each.value.ip_address
  protocol_port  = 80
  subnet_id      = sws_subnet.tiers["web"].id
}

resource "sws_lb_member" "app" {
  for_each       = { for k, v in sws_instance.workloads : k => v if startswith(k, "app-") }
  pool_id        = sws_lb_pool.app.id
  address        = each.value.ip_address
  protocol_port  = 8080
  subnet_id      = sws_subnet.tiers["app"].id
}

resource "sws_lb_health_monitor" "web" {
  pool_id = sws_lb_pool.web.id
  type = "HTTP"
  delay = 5
  timeout = 3
  max_retries = 3
  url_path = "/"
}
resource "sws_lb_health_monitor" "app" {
  pool_id = sws_lb_pool.app.id
  type = "HTTP"
  delay = 5
  timeout = 3
  max_retries = 3
  url_path = "/health"
}

# ── 9. DNS — public + private ─────────────────────────────────────────────
resource "sws_dns_zone" "public" {
  name        = var.domain_name
  description = "Public zone for ${var.domain_name}"
  ttl         = 3600
  email       = "admin@${var.domain_name}"
}

resource "sws_dns_record" "apex" {
  zone_id = sws_dns_zone.public.id
  name = "${var.domain_name}."
  type = "A"
  ttl = 300
  records = [sws_floating_ip.edge[0].address]
}
resource "sws_dns_record" "www" {
  zone_id = sws_dns_zone.public.id
  name = "www.${var.domain_name}."
  type = "A"
  ttl = 300
  records = [sws_floating_ip.edge[0].address]
}
resource "sws_dns_record" "api" {
  zone_id = sws_dns_zone.public.id
  name = "api.${var.domain_name}."
  type = "A"
  ttl = 300
  records = [sws_floating_ip.edge[1].address]
}
resource "sws_dns_record" "cdn" {
  zone_id = sws_dns_zone.public.id
  name = "cdn.${var.domain_name}."
  type = "A"
  ttl = 300
  records = [sws_floating_ip.edge[2].address]
}
resource "sws_dns_record" "mail" {
  zone_id = sws_dns_zone.public.id
  name = "mail.${var.domain_name}."
  type = "MX"
  ttl = 3600
  records = ["10 mx1.privateemail.com.", "10 mx2.privateemail.com."]
}

resource "sws_private_dns_zone" "internal" {
  name        = "internal.${local.prefix}.lan"
  description = "Private DNS for in-spoke service discovery"
}

# ── 10. Tier-3 services — every long-tail one the provider exposes ───────
resource "sws_cache" "session" {
  name = "${local.prefix}-cache"
  config = jsonencode({
    engine          = "redis"
    plan            = "small"
    network_id      = sws_network.spoke.id
    auth_password   = var.cache_password
    persistence     = true
    eviction_policy = "allkeys-lru"
  })
}

resource "sws_queue" "events" {
  name = "${local.prefix}-events"
  config = jsonencode({
    engine     = "rabbitmq"
    plan       = "small"
    network_id = sws_network.spoke.id
  })
}

resource "sws_kafka" "stream" {
  name = "${local.prefix}-kafka"
  config = jsonencode({
    plan       = "small"
    network_id = sws_network.spoke.id
    partitions = 3
  })
}

resource "sws_file_storage" "shared" {
  name = "${local.prefix}-share"
  config = jsonencode({
    size_gb    = 100
    network_id = sws_network.spoke.id
  })
}

resource "sws_bastion" "jump" {
  name = "${local.prefix}-bastion"
  config = jsonencode({
    network_id = sws_network.spoke.id
    plan       = "m1.small"
    cidr_allow = ["0.0.0.0/0"]
  })
}

resource "sws_logging" "central" {
  name = "${local.prefix}-logs"
  config = jsonencode({
    retention_days = 30
    sinks          = ["object-bucket:${local.prefix}-logs"]
  })
}

resource "sws_cdn" "edge" {
  name = "${local.prefix}-cdn"
  config = jsonencode({
    origin_host = "www.${var.domain_name}"
    ttl         = 300
    https_only  = true
  })
}

resource "sws_notification" "ops" {
  name = "${local.prefix}-notify"
  config = jsonencode({
    channels = [
      { type = "email",   target = "ops@${var.domain_name}" },
      { type = "webhook", target = "https://api.${var.domain_name}/notify" }
    ]
  })
}

resource "sws_pipeline" "ci" {
  name = "${local.prefix}-ci"
  config = jsonencode({
    repo   = "https://github.com/example/app"
    branch = "main"
    steps  = ["build", "test", "deploy"]
  })
}

resource "sws_registry" "containers" {
  name = "${local.prefix}-registry"
  config = jsonencode({
    storage_gb = 50
    visibility = "private"
  })
}

resource "sws_backup_policy" "daily" {
  name = "${local.prefix}-backup-daily"
  config = jsonencode({
    schedule       = "0 2 * * *"  # 02:00 daily
    retention_days = 14
    targets        = ["volumes:tagged:backup=true"]
  })
}

resource "sws_serverless_container" "edge_fn" {
  name       = "${local.prefix}-fn"
  image      = "registry.savannaa.com/library/echo:latest"
  network_id = sws_network.spoke.id
}

resource "sws_vault_secret" "db_url" {
  name = "${local.prefix}-db-url"
  config = jsonencode({
    value = "postgresql://spoke_admin:${var.db_admin_password}@${local.prefix}-pg/defaultdb"
    tags  = ["db", "spoke-test"]
  })
}

resource "sws_alarm" "high_cpu" {
  name = "${local.prefix}-cpu-high"
  config = jsonencode({
    metric    = "cpu.utilization"
    threshold = 80
    operator  = ">"
    period    = 60
    actions   = ["notify:${local.prefix}-notify"]
  })
}

resource "sws_tag" "env" {
  name = "${local.prefix}-tag-env-dev"
  config = jsonencode({
    key   = "Environment"
    value = "dev"
  })
}

# ── 11. Kubernetes (opt-in) ──────────────────────────────────────────────
resource "sws_kubernetes_template" "k8s" {
  count               = var.enable_kubernetes ? 1 : 0
  name                = "${local.prefix}-k8s-tpl"
  image               = "Fedora CoreOS 43"
  flavor_id           = "m1.medium"
  master_flavor_id    = "m1.medium"
  external_network_id = var.external_network_id
  keypair_id          = length(sws_keypair.admin) > 0 ? sws_keypair.admin[0].name : "default"
  coe_name            = "kubernetes"
}

resource "sws_kubernetes_cluster" "demo" {
  count               = var.enable_kubernetes ? 1 : 0
  name                = "${local.prefix}-k8s"
  cluster_template_id = sws_kubernetes_template.k8s[0].id
  node_count          = 2
  master_count        = 1
  keypair_id          = length(sws_keypair.admin) > 0 ? sws_keypair.admin[0].name : "default"
}
