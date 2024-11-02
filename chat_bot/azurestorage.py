import os
from typing import Union
from azure.storage.blob import BlobServiceClient, BlobClient, ContentSettings, StandardBlobTier
import azure.storage.blob
from azure.data.tables import TableServiceClient
from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError
from azure.identity import DefaultAzureCredential

"""
Environment variables used for Azure Storage Auto-Configuration:
AZURE_STORAGEBLOB_CONNECTIONSTRING   Required for storage account key auth (if not using AZURE_STORAGEBLOB_RESOURCEENDPOINT)
AZURE_STORAGEBLOB_RESOURCEENDPOINT   Required for default credential auth  (if not using AZURE_STORAGEBLOB_CONNECTIONSTRING)
AZURE_STORAGEBLOB_CONTAINER          Optional, default is 'documents'
"""


class BlobStorage:
    _bsc = None
    _container = ""
    _blob_tier = StandardBlobTier.COOL

    def __init__(self, container : Union[str, None] = None, connection_string : Union[str, None] = None, account_url : Union[str, None] = None, credential = None):
        # set the blob service client
        if connection_string is None and account_url is None:
            if os.getenv("AZURE_STORAGEBLOB_CONNECTIONSTRING"):
                self._bsc = BlobServiceClient.from_connection_string(
                        conn_str=os.getenv("AZURE_STORAGEBLOB_CONNECTIONSTRING"),
                    )
            elif os.getenv("AZURE_STORAGEBLOB_RESOURCEENDPOINT"):
                self._bsc = BlobServiceClient(
                    account_url=os.getenv("AZURE_STORAGEBLOB_RESOURCEENDPOINT"),
                    credential=DefaultAzureCredential()
                )
            else:
                raise ValueError("No connection string or resource endpoint provided")
        elif connection_string is not None:
            if credential is None:
                self._bsc = BlobServiceClient.from_connection_string(conn_str=connection_string)
            else:
                self._bsc = BlobServiceClient.from_connection_string(conn_str=connection_string, credential=credential)
        elif account_url is not None:
            if credential is None:
                self._bsc = BlobServiceClient(account_url=account_url, credential=DefaultAzureCredential())
            else:
                self._bsc = BlobServiceClient(account_url=account_url, credential=credential)
        else:
            raise ValueError("No connection_string or account_url provided")
        # Set the container
        if isinstance(container, str):
            self._container = container
        else:
            self._container = os.getenv("AZURE_STORAGEBLOB_CONTAINER")
        if self._container is None or self._container == "":
            self._container = "documents"
    
    def getStorageAccountName(self) -> str:
        return str(self._bsc.account_name)
    def getStorageContainerName(self) -> str:
        return str(self._container)
    
    def hasFullPath(self, account_name : str, container_name : str, path : str) -> bool:
        if account_name.lower().split(".")[0] != str(self._bsc.account_name).lower().split(".")[0]:
            return False
        if container_name.lower() != self._container.lower():
            return False
        return self._getBlobClientForPath(path).exists()

    def _getBlobClientForPath(self, path : str) -> BlobClient:
        return self._bsc.get_blob_client(container = self._container, blob=path)
    
    def setBlobTier(self, tier : StandardBlobTier):
        self._blob_tier = tier

    def getBlobTier(self):
        return self._blob_tier
    
    def hasPath(self, path : str) -> bool:
        return self._getBlobClientForPath(path).exists()
    
    def uploadBinary(self, path : str, binary, content_settings : Union[None, str, ContentSettings] = None, overwrite : bool = False):
        if isinstance(binary, bytearray):
            binary = bytes(binary)
        try:
            if isinstance(content_settings, str):
                content_settings = ContentSettings(content_settings)
            if not isinstance(content_settings, ContentSettings):
                self._getBlobClientForPath(path).upload_blob(binary, overwrite = overwrite, standard_blob_tier = self._blob_tier)
            else:
                self._getBlobClientForPath(path).upload_blob(binary, overwrite = overwrite, standard_blob_tier = self._blob_tier, content_settings = content_settings)
        except ResourceExistsError:
            return False
        return True

    def downloadBinary(self, path : str) -> Union[None, bytes]:
        try:
            return self._getBlobClientForPath(path).download_blob().readall()
        except ResourceNotFoundError:
            return None
    
    def deletePath(self, path : str) -> bool:
        try:
            self._getBlobClientForPath(path).delete_blob(delete_snapshots="include")
        except ResourceNotFoundError:
            return False
        return True
    
    def listPath(self, path : str) -> list:
        cc = self._bsc.get_container_client(container = self._container)
        a = []
        for blob in cc.list_blobs(name_starts_with = path):
            a.append({
                "Name"         : blob.name,
                "Tier"         : blob.blob_tier,
                "ContentType"  : blob.content_settings.content_type,
                "Created"      : blob.creation_time,
                "LastModified" : blob.last_modified,
                "Size"         : blob.size
            })
        return a
    