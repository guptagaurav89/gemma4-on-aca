targetScope = 'resourceGroup'

@description('Location for all resources')
param location string

@description('Environment name for resource naming')
param environmentName string

@description('Unique suffix for resource names')
param resourceToken string

@description('Username for nginx basic auth')
param proxyAuthUser string = 'admin'

@description('Password for nginx basic auth')
@secure()
param proxyAuthPassword string

@description('GPU workload profile type')
param gpuProfileType string

@description('Hugging Face model repository ID for vLLM to load')
param modelId string

@description('Model name exposed via the OpenAI-compatible API "model" field')
param servedModelName string

@description('Hugging Face access token used to download gated Gemma weights')
@secure()
param huggingFaceToken string = ''

@description('Container image registry prefix (must allow anonymous pull, unless acrPullIdentityId is set)')
param imageRegistry string = 'ssagentfactory.azurecr.io/gemma4-on-aca'

@description('Resource ID of a pre-provisioned user-assigned identity already granted AcrPull on the registry. Set this when the registry does not allow anonymous pull.')
param acrPullIdentityId string = ''

@description('Enable diagnostic logging')
param enableDebugging bool = false

// GPU resource allocation lookup
var gpuResources = gpuProfileType == 'Consumption-GPU-NC24-A100' ? {
  cpu: 16
  memory: '64Gi'
} : {
  cpu: 8
  memory: '56Gi'
}

var baseName = toLower('${environmentName}-${resourceToken}')
var containerAppsEnvironmentName = 'cae-${baseName}'
var vllmAppName = 'vllm-${baseName}'
var nginxAuthProxyAppName = 'proxy-${baseName}'
var logAnalyticsWorkspaceName = 'log-${baseName}'

// ─── Registry auth: managed identity + AcrPull (used when the registry doesn't allow anonymous pull) ───
var useRegistryIdentity = !empty(acrPullIdentityId)
var acrServer = split(imageRegistry, '/')[0]

// ─── Log Analytics (optional) ───
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableDebugging) {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    retentionInDays: 30
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ─── ACA Environment with GPU workload profile ───
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  properties: union({
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
      {
        name: 'GPU'
        workloadProfileType: gpuProfileType
      }
    ]
  }, enableDebugging ? {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace!.properties.customerId
        sharedKey: listKeys(logAnalyticsWorkspace!.id, '2020-08-01').primarySharedKey
      }
    }
  } : {})
}

// ─── vLLM Container App (GPU, internal) ───
resource vllmApp 'Microsoft.App/containerApps@2025-02-02-preview' = {
  name: vllmAppName
  location: location
  identity: useRegistryIdentity ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acrPullIdentityId}': {}
    }
  } : null
  properties: {
    environmentId: containerAppsEnvironment.id
    workloadProfileName: 'GPU'
    configuration: {
      ingress: {
        external: false
        targetPort: 8000
        allowInsecure: false
      }
      registries: useRegistryIdentity ? [
        {
          server: acrServer
          identity: acrPullIdentityId
        }
      ] : null
      secrets: [
        {
          name: 'hf-token'
          value: huggingFaceToken
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'vllm'
          image: '${imageRegistry}/vllm:latest'
          env: [
            {
              name: 'MODEL_ID'
              value: modelId
            }
            {
              name: 'SERVED_MODEL_NAME'
              value: servedModelName
            }
            {
              name: 'HF_TOKEN'
              secretRef: 'hf-token'
            }
            {
              name: 'MAX_MODEL_LEN'
              value: '32768'
            }
            {
              name: 'GPU_MEMORY_UTILIZATION'
              value: '0.90'
            }
          ]
          resources: {
            cpu: gpuResources.cpu
            memory: gpuResources.memory
          }
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
      }
    }
  }
}

// ─── Nginx Auth Proxy (Consumption, external) ───
resource nginxAuthProxyApp 'Microsoft.App/containerApps@2025-02-02-preview' = {
  name: nginxAuthProxyAppName
  location: location
  identity: useRegistryIdentity ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acrPullIdentityId}': {}
    }
  } : null
  properties: {
    environmentId: containerAppsEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        transport: 'Auto'
        allowInsecure: false
      }
      registries: useRegistryIdentity ? [
        {
          server: acrServer
          identity: acrPullIdentityId
        }
      ] : null
      secrets: [
        {
          name: 'basic-auth-password'
          value: proxyAuthPassword
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'nginx-auth-proxy'
          image: '${imageRegistry}/nginx-auth-proxy:latest'
          env: [
            {
              name: 'BACKEND_URL'
              value: vllmApp.properties.configuration.ingress.fqdn
            }
            {
              name: 'BASIC_AUTH_USER'
              value: proxyAuthUser
            }
            {
              name: 'BASIC_AUTH_PASSWORD'
              secretRef: 'basic-auth-password'
            }
            {
              name: 'BACKEND_TIMEOUT'
              value: '600'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// ─── Outputs ───
output AZURE_CONTAINER_APPS_ENVIRONMENT_ID string = containerAppsEnvironment.id
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = containerAppsEnvironment.name
output VLLM_APP_NAME string = vllmApp.name
output NGINX_AUTH_PROXY_APP_NAME string = nginxAuthProxyApp.name
output VLLM_PROXY_ENDPOINT string = nginxAuthProxyApp.properties.configuration.ingress.fqdn
