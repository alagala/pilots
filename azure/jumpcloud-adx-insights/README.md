# Analyze JumpoCloud dataset in Azure Data Explorer

TODO

## Prerequisites

1. Microsoft [Azure subscription](https://azure.microsoft.com/en-us/)
1. [Conda](https://conda.io/projects/conda/en/latest/user-guide/install/index.html) to create a virtual environment with Python 3.6
1. [Azure Functions Core Tools](https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local) (version 2.x) to run the provided Python-based Function locally and publish it to Azure
1. A CI server to run Terraform non-interactively, with a Service Principal (which is an application within Azure Active Directory); or
1. If you plan to run Terraform from your local machine, install:
   - The [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
   - [Terraform](https://www.terraform.io) 

# Run Terraform and setup the environment on Azure

## Create a Service Principal on your local machine using the Azure CLI

Firstly, login to the Azure CLI using:
```shell
$ az login
```
Once logged in - it's possible to list the Subscriptions associated with the account via:
```shell
$ az account list
```

The output will display one or more Subscriptions - with the `id` field being the `SUBSCRIPTION_ID` field referred to in the scripts below.

Should you have more than one Subscription, you can specify the Subscription to use via the following command:
```shell
$ az account set --subscription="SUBSCRIPTION_ID"
```

We can now create the Service Principal which will have permissions to manage resources in the specified Subscription using the following command:
```shell
$ az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/SUBSCRIPTION_ID"
```

This command will output a few values that must be mapped to the Terraform variables. Take note of them because you will need them in the following section:
- `appId` is the `client_id`
- `password` is the `client_secret`
- `tenant` is the `tenant_id`

Finally, since we're logged into the Azure CLI as a Service Principal we recommend logging out of the Azure CLI:
```shell
$ az logout
```

## Configure the Service Principal in Terraform

Store the credentials obtained in the previous step as environment variables:
```shell
$ export ARM_CLIENT_ID=<APP_ID>
$ export ARM_CLIENT_SECRET=<PASSWORD>
$ export ARM_SUBSCRIPTION_ID=<SUBSCRIPTION_ID>
$ export ARM_TENANT_ID=<TENANT>
```

## Run Terraform to create the environment

Clone this repository and modify the project file `poc.tfvars` to enter the values that are right for the deployment of the environment in your Azure subscription:
```
project_name           = <PROJECT_NAME>
project_location       = <AZURE_REGION_TO_DEPLOY_THE_PROJECT>
resgroup_name          = <RESOURCE_GROUP_NAME>
whitelist_ip_addresses = <IP_ADDRESSES_TO_BE_WHITELISTED_BY_STORAGE_FIREWALL>
```
   > **Note**: ensure that the value of the project name is maximum 16 characters in length, othwerwise some resources will not be created properly (as their names will exceed the maximum allowed length).

Run Terraform:
```shell
$ terraform init
$ terraform apply -var-file=poc.tfvars
```

When the execution of the Terraform plan has completed (expect about 10-15 minutes), verify that the required services have been successfully created:

1. Sign in to the [Azure Portal](https://portal.azure.com).

1. In the left pane, select **Resource groups**. If you don't see the service listed, select **All services**, and then select **Resource groups**.

1. You should see a resource group named `<PROJECT_NAME>-poc-rg` (eg. `serverless-poc-rg`).

1. Click on it and observe that the following services have been created:
   - `<PROJECT_NAME><#>`: the **Azure Storage account**, that the JumpCloud data will be archived to.
   - `<PROJECT_NAME>kusto`: the **Azure Data Explorer** cluster which hosts the _jc-system-insights_ database that can be queried with KQL. JumpCloud data is stored in Azure Data Explorer in addition to the storage account above.
   - `<PROJECT_NAME>-funcapp-<#>`: the **Azure Function App**, ie. the serverless compute service that periodically runs functions to download the data from JumpCloud, archive it to the storage account, and store it for analysis in Azure Data Explorer.
   - `<PROJECT_NAME>-app-insights`: the **Azure Application Insights** service that is used to help you monitor the Azure Functions. Consult the [Application Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview) for more details.
   - `<PROJECT_NAME>-service-plan`: the **Azure App Service Plan**, that defines the consumption plan to be used by the Azure Functions (a consumption plan is billed based on per-second resource consumption and executions).
   - `func<PROJECT_NAME><#>`: the **Azure Storage account** used by the Azure Functions to manage triggers and function exections.

## Copy the Terraform output variables

Terraform outputs a few variables that you need to configure the Kafka clients (including the sample Twitter client application provided) to send streaming data to Azure Event Hubs, and to publish the provided Function to Azure:

Copy the following property values and paste them to Notepad or some other text application that you can reference later:
- **eventhub_namespace_name** and **eventhub_primary_connection_string**
- **funcapp_name**

You can also reproduce the values with the following commands:
```shell
$ terraform output eventhub_namespace_name
$ terraform output eventhub_primary_connection_string
$ terraform output funcapp_name
```

# Test the Azure Function locally and publish it to Azure

Create a Python 3.6 environment with Conda, then test the provided Azure Function locally before publishing it to Azure (you will need Conda and the Azure Functions Core Tools installed on your machine - see the [Prerequisites](#Prerequisites) section). After cloning the repository execute the following commands:

```shell
$ conda create -n azure-functions python=3.6
$ conda activate azure-functions
$ pip install -r requirements.txt
```

You can test the function locally by entering:
```shell
$ func host start
```

You should see each each function downloading data from JumpCloud and ingesting it into Azure Data Explorer.

You are now ready to publish the function to Azure, executing the following command (replacing {FUNCAPP_NAME} with the **funcapp_name** value output by Terraform):

```shell
$ func azure functionapp publish {FUNCAPP_NAME} --build remote
```

_Congratulations! You have successfully setup an end-to-end pipeline to download and analyze JumpCloud data with Microsoft Azure services!_

# Cleanup the allocated resources

## Run Terraform to destroy the environment

Run the following Terraform command to cleanup all allocated resources and destroy the environment:
```shell
$ terraform destroy
```