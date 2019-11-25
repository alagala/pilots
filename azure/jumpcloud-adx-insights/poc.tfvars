# Choose a project name with max 16 characters
project_name           = "gtsdataestate"
project_location       = "southeastasia"
resgroup_name          = "gts-data-estate"

# IP address(es) of the machine executing the Terraform script.
# The indicated IP addresses are used to set the Storage firewall rules
# for the purpose of automatically creating the Blob container or
# ADLS filesystem.
whitelist_ip_addresses = ["222.164.176.163"]