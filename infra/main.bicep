targetScope = 'resourceGroup'

@description('Name of the environment used for resource naming')
param environmentName string

@description('Primary location for all resources')
param location string

@description('Password for nginx auth proxy basic authentication')
@secure()
param proxyAuthPassword string

@description('GPU workload profile type')
@allowed([
  'Consumption-GPU-NC8as-T4'
  'Consumption-GPU-NC24-A100'
])
param gpuProfileType string = 'Consumption-GPU-NC8as-T4'

@description('Hugging Face model repository ID for vLLM to load (e.g. google/gemma-4n-e4b-it)')
param modelId string = 'google/gemma-4n-e4b-it'

@description('Model name exposed via the OpenAI-compatible API "model" field')
param servedModelName string = 'gemma4:e4b'

@description('Hugging Face access token used to download gated Gemma weights')
@secure()
param huggingFaceToken string = ''

@description('Container image registry prefix (must allow anonymous pull, unless imageRegistryResourceGroup is set)')
param imageRegistry string = 'ssagentfactory.azurecr.io/gemma4-on-aca'

@description('Resource group of the image registry, in the same subscription. Set this when the registry does not allow anonymous pull, so the container apps use a managed identity + AcrPull role instead.')
param imageRegistryResourceGroup string = ''

@description('Toggle diagnostic logging')
param enableDebugging bool = false

var resourceToken = take(toLower(uniqueString(subscription().id, environmentName, location)), 5)

// ─── Registry auth: managed identity + AcrPull, created up-front so the role assignment exists before the container apps try to pull ───
var useRegistryIdentity = !empty(imageRegistryResourceGroup)
var acrServer = split(imageRegistry, '/')[0]
var acrName = split(acrServer, '.')[0]
var acrPullIdentityName = 'id-${toLower(environmentName)}-${resourceToken}'
// a condition on a cross-resource-group module breaks ARM's dependency validation, so the scope must always resolve to a real resource group
var registryAccessResourceGroup = useRegistryIdentity ? imageRegistryResourceGroup : resourceGroup().name

resource acrPullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (useRegistryIdentity) {
  name: acrPullIdentityName
  location: location
}

module registryAccess 'registry-access.bicep' = {
  name: '${deployment().name}-registry-access'
  scope: resourceGroup(registryAccessResourceGroup)
  params: {
    acrName: acrName
    principalIds: useRegistryIdentity ? [acrPullIdentity!.properties.principalId] : []
  }
}

module resources 'resources.bicep' = {
  name: 'resources'
  params: {
    location: location
    environmentName: environmentName
    resourceToken: resourceToken
    proxyAuthPassword: proxyAuthPassword
    gpuProfileType: gpuProfileType
    modelId: modelId
    servedModelName: servedModelName
    huggingFaceToken: huggingFaceToken
    imageRegistry: imageRegistry
    acrPullIdentityId: useRegistryIdentity ? acrPullIdentity!.id : ''
    enableDebugging: enableDebugging
  }
  dependsOn: [registryAccess]
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_CONTAINER_APPS_ENVIRONMENT_ID string = resources.outputs.AZURE_CONTAINER_APPS_ENVIRONMENT_ID
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = resources.outputs.AZURE_CONTAINER_APPS_ENVIRONMENT_NAME
output VLLM_APP_NAME string = resources.outputs.VLLM_APP_NAME
output NGINX_AUTH_PROXY_APP_NAME string = resources.outputs.NGINX_AUTH_PROXY_APP_NAME
output VLLM_PROXY_ENDPOINT string = resources.outputs.VLLM_PROXY_ENDPOINT
