resource "azurerm_resource_group" "rg" {
  location = var.location
  name     = var.resource_group_name
  tags     = var.tags
}

module  "ServicePrincipal" {
    source = "./modules/ServicePrincipal"
    service_principal_name = var.service_principal_name

    depends_on = [ 
        azurerm_resource_group.rg
     ]
}

resource "azurerm_role_assignment" "rolespn" {

  scope                = "/subscriptions/221f9dbc-1110-4bfe-b299-4b6dd209e015"
  role_definition_name = "Contributor"
  principal_id         = module.ServicePrincipal.service_principal_object_id

  depends_on = [
    module.ServicePrincipal
  ]
} 
module "keyvault" {
  source                      = "./modules/keyvault"
  keyvault_name               = var.keyvault_name
  location                    = var.location
  resource_group_name         = var.resource_group_name
  service_principal_name      = var.service_principal_name
  service_principal_object_id = module.ServicePrincipal.service_principal_object_id
  service_principal_tenant_id = module.ServicePrincipal.service_principal_tenant_id

  depends_on = [
    module.ServicePrincipal
  ]
}
resource "azurerm_key_vault_secret" "newlook-kv-sec" {
  name         = module.ServicePrincipal.client_id
  value        = module.ServicePrincipal.client_secret
  key_vault_id = module.keyvault.keyvault_id

  depends_on = [
    module.keyvault
  ]
}

#create Azure Kubernetes Service
module "aks" {
  source                 = "./modules/aks/"
  service_principal_name = var.service_principal_name
  client_id              = module.ServicePrincipal.client_id
  client_secret          = module.ServicePrincipal.client_secret
  location               = var.location
  resource_group_name    = var.resource_group_name

  depends_on = [
    azurerm_key_vault_secret.newlook-kv-sec
  ]

}
# data "azurerm_container_registry" "acr" {
#   name                = var.acr_name
#   resource_group_name = var.rg_name
# }

# create Azure Container registry
 module "acr" {
  source = "./modules/acr"
  resource_group_name = var.resource_group_name
  location = var.location
  acr_name = var.acr_name
  acr_sku = var.acr_sku
  tags = var.tags
  
 }

resource "azurerm_role_assignment" "acr_pull_role" {
  principal_id         = module.ServicePrincipal.service_principal_object_id
  scope                = module.acr.acr_id
  role_definition_name = "AcrPull"
  skip_service_principal_aad_check = true
   depends_on = [
    module.aks
  ]
}

module "k8s" {
  source                = "./modules/k8s/"
  host                  = "${module.aks.host}"
  client_certificate    = "${base64decode(module.aks.client_certificate)}"
  client_key            = "${base64decode(module.aks.client_key)}"
  cluster_ca_certificate= "${base64decode(module.aks.cluster_ca_certificate)}"
 
}
