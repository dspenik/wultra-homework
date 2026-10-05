environment = "dev"
location    = "austriaeast"
# D2as_v5 is not offered to this subscription in Austria East
node_vm_size    = "Standard_D2s_v6"
gitops_repo_url = "https://github.com/dspenik/wultra-homework.git"

# admin_ip_ranges is not committed (public repository): export TF_VAR_admin_ip_ranges='["<your IP>/32"]'

tags = {
  owner = "platform"
}
