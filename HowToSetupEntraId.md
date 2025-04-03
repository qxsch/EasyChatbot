# How to set up Entra ID for the Web App Authentication

1.  Go to [Entra ID App Registrations](https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/RegisteredApps)
1.  Click on **New Registration**.
1.  Fill in the following fields:
    - **Name**: Enter a name for your app registration (e.g., "EasyChatbot")
    - **Supported account types**: Select "Accounts in this organizational directory only (Single tenant)"
    - **Redirect URI**: Select "Web" and enter the redirect URI for your web app (e.g., `https://<your-web-app-name>.azurewebsites.net/.auth/login/aad/callback`)
1.  Click on **Register**.
1.  After the registration is complete, you will be redirected to the app registration's overview page.
1.  Go to the **Authentication** tab in the left sidebar.
    1. Under Select the tokens you want to configure, just select ``ID tokens (used for implicit and hybrid flows)``.
    1. Disable the **App Instance Proprty Lock**
1.  Go to the **API permissions** tab in the left sidebar.
    1. Click on **Add a permission**.
    1. Select **Microsoft Graph**.
    1. Select **Delegated permissions**.
    1. Search for and select the following permissions:
        - `openid`
        - `profile`
        - `email`
    1. Click on **Add permissions**.
    1. Click on **Grant admin consent for <your-tenant-name>** to grant the permissions.
1.  Go to the **Expose an API** tab in the left sidebar.
    1. Click on **Add a scope**.
    1. Enter the following details:
        - **Scope name**: `user_impersonation`
        - **Who can consent?**: `Admins and users`
        - **Admin consent display name**: `Access EasyChatbot`
        - **Admin consent description**: `Allows the app to access EasyChatbot on behalf of the signed-in user`
        - **State**: `Enabled`
    1. Click on **Add scope**.
1.  Go to the **Certificates & secrets** tab in the left sidebar.
    1. Click on **New client secret**.
    1. Enter a description for the client secret (e.g., "EasyChatbot Secret").
    1. Select an expiration period (e.g., "In 6 months").
    1. Click on **Add**.
    1. Copy the generated client secret value and store it securely (you will need it later).

