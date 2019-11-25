variable "project_name" {
  default = "gtsdataestate"
}

variable "project_location" {
  default = "southeastasia"
}

variable "resgroup_name" {
  default = "gts-data-estate"
}

variable "whitelist_ip_addresses" {
  type    = "list"
  default = ["127.0.0.1"]
}

#
# Configure the Microsoft Azure Provider.
#
provider "azurerm" {
  # This AzureRM Provider is configured to authenticate to Azure
  # using a Service Principal with a Client Secret - therefore
  # ensure that you have exported the following environment variables:
  
  # ARM_CLIENT_ID       = "..."
  # ARM_CLIENT_SECRET   = "..."
  # ARM_SUBSCRIPTION_ID = "..."
  # ARM_TENANT_ID       = "..."

  version = "=1.36.0"
}

resource "random_integer" "ri" {
  min = 10000
  max = 99999
}

#
# Configure the resource group.
#
resource "azurerm_resource_group" "poc_rg" {
  name     = "${var.resgroup_name}"
  location = "${var.project_location}"
}

#
# Configure the ADLS Storage account that will be used to land JumpCloud data to.
#
resource "azurerm_storage_account" "poc_storage_account" {
  name                     = "${var.project_name}${random_integer.ri.result}"
  resource_group_name      = "${azurerm_resource_group.poc_rg.name}"
  location                 = "${azurerm_resource_group.poc_rg.location}"
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = "true"

  #network_rules {
  #  bypass                 = ["AzureServices"]
  #}
}

resource "azurerm_storage_data_lake_gen2_filesystem" "gen2_fs" {
  name               = "jc-data"
  storage_account_id = "${azurerm_storage_account.poc_storage_account.id}"
}

#
# Create the Azure Data Explorer (Kusto) cluster and database used to analyze JumpCloud data.
#
resource "azurerm_kusto_cluster" "poc_kusto_cluster" {
  name                = "${var.project_name}-kusto"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"

  sku {
    name     = "Standard_D13_v2"
    capacity = 2
  }
}

resource "azurerm_kusto_database" "poc_kusto_sysinsights_db" {
  name                = "jc-system-insights"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  cluster_name        = "${azurerm_kusto_cluster.poc_kusto_cluster.name}"

  hot_cache_period    = "P14D"
  soft_delete_period  = "P31D"
}

#
# Configure the Storage account needed by the Function App to manage triggers and log function executions.
#
resource "azurerm_storage_account" "func_storage_account" {
  name                     = "func${var.project_name}${random_integer.ri.result}"
  resource_group_name      = "${azurerm_resource_group.poc_rg.name}"
  location                 = "${azurerm_resource_group.poc_rg.location}"
  account_kind             = "Storage"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Disabling the network rules, otherwise the deployment of the Function App fails:
  # https://github.com/terraform-providers/terraform-provider-azurerm/issues/3816
  #network_rules {
  #  bypass                 = ["AzureServices"]
  #}
}

#
# Configure the Azure Application Insights service.
#
resource "azurerm_application_insights" "poc_app_insights" {
  name                = "${var.project_name}-app-insights"
  location            = "${azurerm_resource_group.poc_rg.location}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  application_type    = "other"
}

#
# Configure the Function App, using a Consumption Plan.
#
resource "azurerm_app_service_plan" "poc_app_service_plan" {
  name                = "${var.project_name}-service-plan"
  location            = "${azurerm_resource_group.poc_rg.location}"
  resource_group_name = "${azurerm_resource_group.poc_rg.name}"
  kind                = "FunctionApp"

  # Force the creation of a Linux instance by setting 'reserved' to true.
  reserved            = true

  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_function_app" "poc_function_app" {
  name                      = "${var.project_name}-funcapp-${random_integer.ri.result}"
  location                  = "${azurerm_resource_group.poc_rg.location}"
  resource_group_name       = "${azurerm_resource_group.poc_rg.name}"
  app_service_plan_id       = "${azurerm_app_service_plan.poc_app_service_plan.id}"
  storage_connection_string = "${azurerm_storage_account.func_storage_account.primary_connection_string}"
  version                   = "~2"

  app_settings {
    "APPINSIGHTS_INSTRUMENTATIONKEY"   = "${azurerm_application_insights.poc_app_insights.instrumentation_key}"
    "FUNCTIONS_WORKER_RUNTIME"         = "python"
    "JUMPCLOUD_DATA_CONNECTION_STRING" = "${azurerm_storage_account.poc_storage_account.primary_connection_string}"
  }
}

output "funcapp_name" {
  value = "${azurerm_function_app.poc_function_app.name}"
}

# Generate the function
resource "local_file" "functions_local_settings" {
  sensitive_content = <<EOF
{
    "IsEncrypted": false,
    "Values": {
      "FUNCTIONS_WORKER_RUNTIME": "python",
      "FUNCTIONS_EXTENSION_VERSION": "~2",
      "AzureWebJobsStorage": "${azurerm_storage_account.func_storage_account.primary_connection_string}",
      "JUMPCLOUD_DATA_CONNECTION_STRING": "${azurerm_storage_account.poc_storage_account.primary_connection_string}"
    }
}
EOF

  filename = "./functions/local.settings.json"

  provisioner "local-exec" {
    command = "chmod 664 ./functions/local.settings.json"
  }
}

#
# Secure the Storage Account by enabling firewall rules.
#
#resource "null_resource" "azure_cli" {
#  provisioner "local-exec" {
#    command = "./set-storage-network-rules.sh"
#
#    environment {
#      resourceGroup          = "${azurerm_resource_group.poc_rg.name}"
#      storageAccount         = "${azurerm_storage_account.poc_storage_account.name}"
#      whitelistedIPAddresses = "${join(",", concat(var.whitelist_ip_addresses, split(",", azurerm_function_app.poc_function_app.possible_outbound_ip_addresses)))}"
#    }
#  }
#
#  triggers = {
#    ip_addresses = "${azurerm_function_app.poc_function_app.possible_outbound_ip_addresses}"
#  }
#
#  depends_on = ["azurerm_storage_account.poc_storage_account", "azurerm_function_app.poc_function_app"]
#}