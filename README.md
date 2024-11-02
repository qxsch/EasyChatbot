# Easy Chatbot

An Easy Chatbot Interface

## How to Setup?

1. Put your pdf documents in the [pdf_documents folder](pdf_documents)
1. Run the setup script  ( You can check the parameters in the [deployment.bicep](iac/deployment.bicep) file )
    ```pwsh
    .\iac\deployChatbot.ps1 -ResourceGroupName "easychatbot" -Location "northeurope" -
    ```
1. Login to the chatbot interface and chat with your pdf data



```python
from azure.storage.blob import BlobClient
from azure.identity import DefaultAzureCredential

def get_blob_client(environment_name, environment_value, container_name, blob_name):
    if environment_name.startswith("AZURE_STORAGEBLOB_"):
        if environment_name.endswith("_CONNECTIONSTRING"):
            return BlobClient.from_connection_string(
                conn_str=environment_value,
                container_name=container_name,
                blob_name=blob_name
            )
        elif environment_name.endswith("_RESOURCEENDPOINT"):
            return BlobClient(
                account_url=environment_value,
                container_name=container_name,
                blob_name=blob_name,
                credential=DefaultAzureCredential()
            )
    return None

# Example usage
environment_name = "AZURE_STORAGEBLOB_CONNECTIONSTRING"
environment_value = "your_connection_string"
container_name = "your_container_name"
blob_name = "your_blob_name"

blob_client = get_blob_client(environment_name, environment_value, container_name, blob_name)
```


```python	
import os
from azure.search.documents import SearchClient
from azure.identity import DefaultAzureCredential, AzureAuthorityHosts

# Azure Public Cloud
audience = "https://search.windows.net"
authority = AzureAuthorityHosts.AZURE_PUBLIC_CLOUD

service_endpoint = os.environ["AZURE_SEARCH_ENDPOINT"]
index_name = os.environ["AZURE_SEARCH_INDEX_NAME"]
credential = DefaultAzureCredential(authority=authority)

search_client = SearchClient(
    endpoint=service_endpoint, 
    index=index_name, 
    credential=credential, 
    audience=audience)

search_index_client = SearchIndexClient(
    endpoint=service_endpoint, 
    credential=credential, 
    audience=audience)
```


```python
# Configure the role assignments from Azure OpenAI system assigned managed identity to Azure search service. Required roles: Search Index Data Reader, Search Service Contributor.
# Configure the role assignments from the user to the Azure OpenAI resource. Required role: Cognitive Services OpenAI User.
# https://learn.microsoft.com/en-us/azure/ai-services/openai/references/azure-search?tabs=python#system-assigned-managed-identity-authentication-options
# https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/on-your-data-best-practices
# https://learn.microsoft.com/en-us/azure/search/search-howto-indexing-azure-blob-storage#add-search-fields-to-an-index
import os
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

endpoint = os.environ.get("AzureOpenAIEndpoint")
deployment = os.environ.get("ChatCompletionsDeploymentName")
search_endpoint = os.environ.get("SearchEndpoint")
search_index = os.environ.get("SearchIndex")

token_provider = get_bearer_token_provider(DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default")

client = AzureOpenAI(
    azure_endpoint=endpoint,
    azure_ad_token_provider=token_provider,
    api_version="2024-02-01",
)

completion = client.chat.completions.create(
    model=deployment,
    messages=[
        {
            "role": "user",
            "content": "Who is DRI?",
        },
    ],
    extra_body={
        "data_sources": [
            {
                "type": "azure_search",
                "parameters": {
                    "endpoint": search_endpoint,
                    "index_name": search_index,
                    "authentication": {
                        "type": "system_assigned_managed_identity"
                    },
                    # "filter": ""  # optional filter for the search query
                    "top_n_documents": 5,
                    "embedding_dependency": {
                        "type": "deployment_name",
                        "deployment_name": "ada2"
                    }
                    "query_type": "vector_semantic_hybrid",
                    "semantic_configuration": "richtlinien-semantic-configuration",
                    "include_contexts": [
                        "citations",
                        "intent"
                    ]
                }
            }
        ]
    }
)


print(completion.model_dump_json(indent=2))
```
