# Easy Chatbot

An Easy Chatbot Interface

* Automatically generates the azure resources needed for the chatbot
* Uploads the pdf documents to an azure storage account
* Indexes the pdf documents with azure search (Vectorized, Hybrid and Semantic Search)
* Uses OpenAI to generate responses to user input with links to the pdf documents (citation to page)
* On click it will open the pdf document at the correct page


## Prerequisites

- PowerShell 7+ ([Installation instructions](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4))
- Azure PowerShell Az Module ([Installation instructions](https://learn.microsoft.com/en-us/powershell/azure/install-azps-windows?view=azps-12.4.0&tabs=powershell&pivots=windows-psgallery))
- Bicep CLI ([Installation instructions](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install#windows))

## How to Setup?

1. Put your pdf documents in the [pdf_documents folder](pdf_documents)
1. Create your users.json file (see [users.json](sample-user.json) for an example)
1. Fine tune the [system-prompt.md](system-prompt.md) and [system-prompt-fewshot-examples.md](system-prompt-fewshot-examples.md) files
1. Run the setup script  ( You can check the parameters in the [deployment.bicep](iac/deployment.bicep) file )
    ```pwsh
    # create a resource group
    New-AzResourceGroup -Name "easychatbot" -Location northeurope
    # deploy the chatbot - you require owner role on the resource group
    .\iac\deployChatbot.ps1 -ResourceGroupName "easychatbot" -Location "northeurope"
    ```
1. Login to the chatbot interface and chat with your pdf data

## Files required for the setup

### users.json
This file contains the users that can login to the chatbot interface. The file should be in the same folder as the [sample-user.json](sample-user.json) file.
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

        // role allowed values: admin, user
        "role": "admin"
    }
]
```
You can also hash all plaintext passwords with the following command:
```pwsh
.\iac\hashPasswords.ps1
```


### system-prompt.md
The [system-prompt.md](system-prompt.md) contains the dos and donts for the chatbot. What it should do, shouldn't do and how it should behave.
```txt
You are a helpful chatbot, that helps the user to find information in documents.
You refuse to talk about politics, religion or other sensitive topics. Instead, you redirect the user to your role.
```

### system-prompt-fewshot-examples.md
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

