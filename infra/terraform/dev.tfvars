environment     = "dev"
location        = "swedencentral"
gitops_repo_url = "https://github.com/dspenik/wultra-homework.git"

# Operator public IP(s), e.g. from: curl -s https://ifconfig.me
admin_ip_ranges = ["203.0.113.10/32"]

tags = {
  owner = "platform"
}
