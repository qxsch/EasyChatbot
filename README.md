# Easy Chatbot

An Easy Chatbot Interface

## How to Setup?

1. Put your pdf documents in the [pdf_documents folder](pdf_documents)
1. Run the setup script  ( You can check the parameters in the [deployment.bicep](iac/deployment.bicep) file )
    ```pwsh
    .\iac\deployChatbot.ps1 -ResourceGroupName "easychatbot" -Location "northeurope" -
    ```
1. Login to the chatbot interface and chat with your pdf data

## Files required for the setup

### users.json
This file contains the users that can login to the chatbot interface. The file should be in the same folder as the [sample-user.json](sample-user.json) file.
It has the following structure:
```json
[
    {
        "username": "admin",  // username should be unique
        "password": "admin",  // password can be plaintext, but should be hashed. In this case it has to begin with 'sha256:' and then the hashed password (f,e, "admin" = "sha256:8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918")
        "role": "admin"       // allowed values: admin, user
    }
]
```

### system-prompt.txt
The [system-prompt.txt](system-prompt.txt) contains the dos and donts for the chatbot. What it should do, shouldn't do and how it should behave.
```txt
You are a helpful chatbot, that helps the user to find information in documents.
You refuse to talk about politics, religion or other sensitive topics. Instead, you redirect the user to your role.
```

### system-prompt-fewshot-examples.txt
The [system-prompt-fewshot-examples.txt](system-prompt-fewshot-examples.txt) contains the examples for the the chatbot to better understand the user input.
```txt
"blablabla" means you talk a lot of nonsense.
"wooohhhoooo" means you are very happy.
```


## Supported Enviroment Variables

| Variable Name | Description | Example |
| --- | --- | --- |
| CHATBOT_SECRET_KEY | Required, Secret Key for the chatbot interface | keepItSecretAndDoNotTellAnyone |
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
- exactly one of the following varibles is required:
  - AZURE_STORAGEBLOB_CONNECTIONSTRING
  - AZURE_STORAGEBLOB_RESOURCEENDPOINT
- and all of the following variables are required:
  - OPENAI_API_BASE
  - AZURESEARCH_API_BASE


