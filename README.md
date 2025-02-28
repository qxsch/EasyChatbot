# Easy Chatbot

An Easy Chatbot Interface

* Automatically generates the azure resources needed for the chatbot
* Uploads the pdf documents to an azure storage account
* Indexes the pdf documents with azure search (Vectorized, Hybrid and Semantic Search)
* Uses OpenAI to generate responses to user input with links to the pdf documents (citation to page)
* On click it will open the pdf document at the correct page
* Supports multiple users with different roles (roles can be used to filter the search results and generate more relevant responses)
* Supports streaming for low-latency responses
* Supports local and Entra ID authentication (through web app easy auth)


## Prerequisites

> [!TIP]
> In case you use the [Azure Cloud Shell](https://learn.microsoft.com/en-us/azure/cloud-shell/overview), most required components are already installed.
>
> You just need to start the Cloud Shell and do this: ``Install-Module -Name Az.Search``

For local installation, you have to install the following components:

- PowerShell 7+ ([Installation instructions](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4))
- Azure PowerShell Az Module ([More information here](https://learn.microsoft.com/en-us/powershell/azure/install-azps-windows?view=azps-12.4.0&tabs=powershell&pivots=windows-psgallery))
  ```pwsh
  Install-Module -Name Az -AllowClobber
  Install-Module -Name Az.Search
  Connect-AzAccount # login
  ```
- Bicep CLI ([Installation instructions](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install#windows))

## How to Setup?

1. Put your pdf documents in the [pdf_documents folder](pdf_documents)
1. Create your users.json file (see [sample-users.json](sample-users.json)) or use the example ``cp sample-users.json users.json``
1. Fine tune the [system-prompt.md](system-prompt.md) and [system-prompt-fewshot-examples.md](system-prompt-fewshot-examples.md) files
1. (Optional) In case you want to use entra id authentication, follow this guide to set up a new app registration: [Use Entra in App Service](https://learn.microsoft.com/en-us/azure/app-service/configure-authentication-provider-aad?tabs=workforce-configuration#configure-client-apps-to-access-your-app-service)
1. Run the setup script  ( You can check the parameters in the [deployment.bicep](iac/deployment.bicep) file )
    ```pwsh
    # create a resource group
    New-AzResourceGroup -Name "easychatbot" -Location northeurope
    # deploy the chatbot - you require owner role on the resource group
    .\iac\deployChatbot.ps1 -ResourceGroupName "easychatbot" -Location "northeurope"
    # OR use the below line in case you want to use entra id authentication
    # .\iac\deployChatbot.ps1 -ResourceGroupName "easychatbot" -Location "northeurope" -entraClientId (Read-Host -Prompt "Client ID")  -entraClientSecret (Read-Host -AsSecureString -Prompt "Client Secret")
    ```
1. Login to the chatbot interface and chat with your pdf data

## Files required for the setup

### users.json
This file contains the users that can login to the chatbot interface. The file should be in the same folder as the [sample-users.json](sample-users.json) file.
It has the following structure:
```json
[
    {
        // username should be unique
        "username": "admin",
        
        // password can be plaintext, but should be hashed.
        // In this case it has to begin with 'sha256:' and then the hashed password
        // (f,e, "admin" = "sha256:8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918")
        "password": "admin",

        // role allowed values: see roles.json
        "role": "admin"
    }
]
```
You can also hash all plaintext passwords with the following command:
```pwsh
.\iac\hashPasswords.ps1
```

### roles.json (optional)
This file is **optional** and contains the roles. You can define custom filters for azure search in the filter field or use the blobPathStartsWith field to define a filter for the blob path.

It essential in case you want to filter the search results based on the user role.
```json
[
    {
        "role": "admin",
        "Description": "Can find all documents because there is no filter and no blobPathStartsWith defined"
    },
    {
        "role": "limited-access-to-myfolder",
        "Description": "Can access the myfolder in documents container of blob storage",
        "filter": "search.ismatch('\"*.blob.core.windows.net\\/documents\\/myfolder\\/*\"', 'metadata_storage_path')"
    },
    {
        "role": "alternative-limited-access-to-myfolder",
        "Description": "Can access the myfolder in documents container of blob storage",
        "blobPathStartsWith": "/myfolder/"
    }
]
```

Links to filter:
- [Azure Search Filter Syntax](https://learn.microsoft.com/en-us/azure/search/search-query-odata-filter)
- search.ismatch [Lucene Query Syntax](https://learn.microsoft.com/en-us/azure/search/query-lucene-syntax)


### system-prompt.md
The [system-prompt.md](system-prompt.md) contains the dos and donts for the chatbot. What it should do, shouldn't do and how it should behave.
```txt
You are a helpful chatbot, that helps the user to find information in documents.
You refuse to talk about politics, religion or other sensitive topics. Instead, you redirect the user to your role.
```

### system-prompt-fewshot-examples.md (optional)
The [system-prompt-fewshot-examples.md](system-prompt-fewshot-examples.md) contains the examples for the the chatbot to better understand the user input.
- Example to Explain words:
  ```md
  - "blablabla" means you talk a lot of nonsense.
  - "wooohhhoooo" means you are very happy.
  ```
- Example to clarify expected output:
  ```md
  - User: Where is the best place to go skiing? System action: Search and provide answer
  - User: What are my latest bookings? System action: Let the user know that you can't help with that.
  - User: Which hotel offers suite room? System  action: Search and provide answer
  - User: Is there a room available in Zurich on Mach 24th? System action: Let the user know that you can't help with that.
  ```


## Supported Enviroment Variables

Documentation for the supported environment variables (required and optional) for the chatbot interface.
You don't need to set the environment variables, since the [deployment.bicep](iac/deployment.bicep) file will set everything for you.

| Variable Name | Description | Example |
| --- | --- | --- |
| CHATBOT_SECRET_KEY | Required, Secret Key for the chatbot interface (used for user login cookie) | keepItSecretAndDoNotTellAnyone |
| CHATBOT_STREAMING | Optional, Enable or disable streaming (default: true) | false |
| AZURE_STORAGEBLOB_CONNECTIONSTRING | Required for storage account key auth (if not using AZURE_STORAGEBLOB_RESOURCEENDPOINT)  |  DefaultEndpointsProtocol=https;AccountName=your_account_name;AccountKey=your_account_key;EndpointSuffix=core.windows.net |
| AZURE_STORAGEBLOB_RESOURCEENDPOINT | Required for default credential Entra ID auth (if not using AZURE_STORAGEBLOB_CONNECTIONSTRING) | https://your_account_name.blob.core.windows.net |
| AZURE_STORAGEBLOB_CONTAINER | Optional Azure Storage Blob Container Name  (Default: documents) | documents |
| OPENAI_API_BASE | Required, OpenAI API Base URL | https://myazureopenainame.openai.com |
| OPENAI_API_KEY | Optional, if not set will use default credential Entra ID auth | your_openai_api_key |
| OPENAI_DEPLOYMENT_NAME | Optional, default is 'gpt-4o' | gpt-4o |
| OPENAI_EMBEDDING_DEPLOYMENT_NAME | Optional, default is 'text-embedding-ada-002' | text-embedding-ada-002 |
| AZURESEARCH_API_BASE | Required, Azure Search API Base URL | https://myazuresearchname.search.windows.net |
| AZURESEARCH_API_KEY | Optional, if not set will use managed identity of open ai service | your_azuresearch_api_key |
| AZURESEARCH_INDEX_NAME | Optional, default is 'documents' | documents |
| USE_AUTH_TYPE | Optional, possible values are 'local' and 'aad'. Default is 'local' | local |


Summarized:
- **exactly one** of the following variables is required:
  - AZURE_STORAGEBLOB_CONNECTIONSTRING
  - AZURE_STORAGEBLOB_RESOURCEENDPOINT
- and **all of** the following variables are required:
  - CHATBOT_SECRET_KEY
  - OPENAI_API_BASE
  - AZURESEARCH_API_BASE


# Useful Links
Useful links:
- https://learn.microsoft.com/en-us/azure/ai-services/openai/references/azure-search?tabs=python
- https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/on-your-data-best-practices
- https://learn.microsoft.com/en-us/azure/search/search-howto-indexing-azure-blob-storage

