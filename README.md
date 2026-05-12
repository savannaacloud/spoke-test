# spoke-test

Terraform that provisions **every typed resource** the
[`savannaacloud/sws`](https://registry.terraform.io/providers/savannaacloud/sws/latest)
provider exposes — at least once each, with several multiplied out via
`for_each` / `count` so the deployed footprint hits **100+ OpenStack
objects** on a single spoke.

Use it to:

- **Smoke-test** a region after a kolla redeploy
- **Seed** a demo environment that touches every console section in one shot
- **Pre-flight** any provider version bump before customers feel it
- **Stress-test** quota / scheduler limits with a known-good baseline

---

## What you get

Default scale (`tier_workload_count = 3`, `enable_kubernetes = false`)
deploys **~110 objects**. Bump the workload variable up for heavier load,
or down to 1 for a fast verification.

| Category | Resource types | Default count | Notes |
|---|---|---|---|
| Identity | `sws_keypair` | 2 | admin + ops personas |
| Networking | `sws_network`, `sws_subnet`, `sws_router`, `sws_router_interface`, `sws_floating_ip`, `sws_vpc_peering` | 2 + 3 + 1 + 3 + 5 + 1 = **15** | Spoke + transit, web/app/worker subnets |
| Security | `sws_security_group`, `sws_security_group_rule` | 5 + 16 = **21** | Web/app/worker/db/lb tiers, 80/443/22/8080/5432/3306/ICMP |
| Compute | `sws_instance` | 9 | 3 tiers × 3 workloads (web-1 gets public IP) |
| Block storage | `sws_volume`, `sws_volume_attachment`, `sws_volume_snapshot` | 9 + 9 + 9 = **27** | One 20 GB SSD per workload + baseline snapshot |
| Object storage | `sws_object_bucket` | 3 | assets / logs / backups (backups versioned) |
| Managed DB | `sws_managed_database` | 2 | PostgreSQL 16 + MySQL 8.4 |
| Load balancer | `sws_load_balancer`, `sws_lb_listener`, `sws_lb_pool`, `sws_lb_member`, `sws_lb_health_monitor` | 2 + 3 + 2 + 6 + 2 = **15** | Public + internal LBs |
| DNS | `sws_dns_zone`, `sws_dns_record`, `sws_private_dns_zone` | 1 + 5 + 1 = **7** | apex, www, api, cdn, mail (MX) + internal zone |
| Tier-3 long-tail | `sws_cache`, `sws_queue`, `sws_kafka`, `sws_file_storage`, `sws_bastion`, `sws_logging`, `sws_cdn`, `sws_notification`, `sws_pipeline`, `sws_registry`, `sws_backup_policy`, `sws_serverless_container`, `sws_vault_secret`, `sws_alarm`, `sws_tag` | 15 | Every Tier-3 generic resource the provider ships |
| Kubernetes (opt-in) | `sws_kubernetes_template`, `sws_kubernetes_cluster` | 0 by default, 2 if `enable_kubernetes=true` | Adds 1 master + 2 worker instances under the cluster |

**Provider coverage**: ALL 40 typed resource types currently exposed by
`savannaacloud/sws ~> 0.4`. See *Out-of-scope* below for the gap.

---

## Out-of-scope (yet)

The savannaa platform has many more services than the provider currently
models. Those need provider-side Go code before they can be
Terraformed:

| Service area | Status | Workaround today |
|---|---|---|
| AI Cloud (managed model endpoints, vector DB, etc.) | No provider resources | Provision via console / `sws` CLI |
| Website Hosting (shared cPanel-style) | No provider resources | Console wizard |
| Marketplace one-click apps (80+) | No provider resources | Marketplace > deploy |
| Auto Scaling Groups (AWS-style) | No provider resources | Console wizard |
| Custom Apps stacks | No provider resources | `sws_serverless_container` covers the basic shape |
| NVA Firewall marketplace apps | No provider resources | Use `sws_instance` with a marketplace image name |
| Bare Metal (Ironic) | No provider resources | Console order form |
| Dedicated Servers catalog | No provider resources | Console |
| Cost Budgets / Allocation / Alerts | No provider resources | Console (these are user-DB-side, not OpenStack) |
| Compliance / Audit export | No provider resources | Console |
| Activity Log query | No provider resources | Console / `sws activity` CLI |
| Identity / Roles | No provider resources | Console — sensitive, intentionally not exposed |

If you want any of those Terraformed, the path is a PR to
[`savannaacloud/terraform-provider-sws`](https://github.com/savannaacloud/terraform-provider-sws)
adding the resource — the Tier-3 generic `config = jsonencode(...)`
pattern is cheap to extend (cache / queue / kafka / etc. are all that
shape).

---

## Prerequisites

1. **Savannaa account** with API access (Account → API Keys).
2. **Terraform ≥ 1.4** (protocol-6 support — earlier versions reject the provider).
3. (Optional) SSH public key to log into the test instances / bastion.
4. **Quota headroom**:
   - 9-15 instances (default scale) × m1.small/medium
   - ~18 vCPU, ~36 GB RAM, ~180 GB ephemeral disk
   - ~9 cinder volumes × 20 GB = 180 GB block storage
   - ~5 floating IPs, ~15 security-group rules, ~3 subnets
   - On a fresh project the defaults comfortably fit. If you've stood
     up other examples first, `terraform destroy` them or trim
     `tier_workload_count`.

---

## Step-by-step

```bash
# 1. Clone the repo
git clone https://github.com/savannaacloud/spoke-test.git
cd spoke-test

# 2. Credentials + region
export SWS_API_URL=https://savannaa.com
export SWS_API_KEY=<your-api-key>
export SWS_REGION=ng-lagos-1        # or ng-abuja-1

# 3. Initialise — downloads the provider from the public Registry
terraform init

# 4. Plan — confirm what's about to land
terraform plan \
  -var "ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" \
  -var "domain_name=mydomain.example.com" \
  -var "tier_workload_count=3"

# 5. Apply — takes ~5-10 min (managed DB + LB warmup are the slow bits)
terraform apply -auto-approve \
  -var "ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" \
  -var "domain_name=mydomain.example.com"

# 6. Read outputs
terraform output summary    # counts per category
terraform output            # all outputs (IDs, IPs, etc.)

# 7. Spot-check in the console
#    Compute > Instances    9 workloads + 1 bastion
#    Storage > Volumes      9 attached SSDs
#    Storage > Snapshots    9 baselines
#    Storage > Buckets      3 (assets/logs/backups)
#    Database               2 (postgres + mysql) ACTIVE
#    Networking > LBs       2, members healthy
#    Networking > DNS       your zone + 5 records
#    Networking > Cache/Queue/Kafka  3 brokers
#    Networking > File Storage       1 share
#    Networking > Bastion   1 jump host
#    Developer Tools        registry, pipeline, serverless container, logging, alarm
#    Costs                  tag visible on every tagged resource

# 8. To enable Kubernetes (adds ~15 min apply time + 3 m1.medium VMs)
terraform apply -auto-approve \
  -var "ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" \
  -var "domain_name=mydomain.example.com" \
  -var "enable_kubernetes=true"

# 9. Destroy when done
terraform destroy -auto-approve \
  -var "ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" \
  -var "domain_name=mydomain.example.com"
```

---

## Variables

| Variable | Type | Default | Notes |
|---|---|---|---|
| `ssh_public_key` | string | `""` | Empty disables keypair create. |
| `domain_name` | string | `spoke-test.example.com` | Public DNS zone. Use a domain you own for live resolution. |
| `db_admin_password` | string | `ChangeMe-Spoke-Test-2026` | Postgres + MySQL admin password. **Change for non-throwaway use.** |
| `cache_password` | string | `ChangeMe-Cache-2026` | Redis AUTH. **Change.** |
| `tier_workload_count` | number | `3` | Instances per app tier. `1` = fast smoke test (~80 objects), `5` = load test (~140 objects). |
| `enable_kubernetes` | bool | `false` | Provision k8s template + cluster. Adds ~15 min + 3 m1.medium VMs. |

---

## Verified vs experimental

Recent backend / provider fixes ironed out most known issues. Today's
status:

| Resource family | Status |
|---|---|
| `sws_network` + subnet + router + floating-IP | ✅ verified in this session |
| `sws_security_group` + rules | ✅ idempotent on duplicate (PR #301) |
| `sws_keypair` + instance + volumes | ✅ verified |
| `sws_object_bucket` | ✅ Abuja=RGW, Lagos=Swift both work (PR #298) |
| `sws_managed_database` | ✅ verified (PR #288 plan pricing) |
| `sws_load_balancer` + listener + pool + member + monitor | ✅ verified |
| `sws_dns_zone` + record + private_dns_zone | ✅ verified |
| `sws_vpc_peering` | ✅ verified after PRs #300 / #301 / #303 |
| `sws_cache`, `sws_queue`, `sws_file_storage`, `sws_bastion`, `sws_kafka`, `sws_logging`, `sws_cdn`, `sws_notification`, `sws_pipeline`, `sws_registry`, `sws_backup_policy`, `sws_serverless_container`, `sws_vault_secret`, `sws_alarm`, `sws_tag` | 🟡 Tier-3 generic — each may need backend `_unpack_config` if a 400 surfaces (the pattern in `routers/vpc_peering.py:_unpack_config()` solves it in one copy-paste) |
| `sws_kubernetes_cluster` | 🟡 opt-in, verify Magnum is healthy before flipping |

If any Tier-3 resource fails with `400 ... is required`, that's
diagnostic for the backend not unpacking `config` JSON before reading
top-level fields. Open an issue or DM — one-line backend fix per
service.

---

## Layout

```
spoke-test/
├── versions.tf         Provider pin (sws ~> 0.4)
├── variables.tf        6 tunables
├── main.tf             11 sections, every resource type
├── outputs.tf          Per-category counts + IDs/IPs
└── README.md           This file
```

---

## License

Mozilla Public License 2.0 — same as
[savannaacloud/terraform-provider-sws](https://github.com/savannaacloud/terraform-provider-sws).
