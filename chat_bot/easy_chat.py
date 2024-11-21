import os, re
from urllib.parse import unquote, quote
from typing import Union, List, Generator
from openai import AzureOpenAI
from openai.types.chat import ChatCompletion, ChatCompletionChunk
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from .iam import ChatbotRole
import json

"""
Environment variables used for EasyChatClient Auto-Configuration:
OPENAI_API_BASE             Required
OPENAI_API_KEY              Optional, if not set will use default credential
OPENAI_DEPLOYMENT_NAME      Optional, default is 'gpt-4o'
OPENAI_EMBEDDING_DEPLOYMENT_NAME    Optional, default is 'text-embedding-ada-002'
AZURESEARCH_API_BASE        Required
AZURESEARCH_API_KEY         Optional, if not set will use managed identity of open ai
AZURESEARCH_INDEX_NAME      Optiona, default is 'documents'
"""

def get_json_serializable_response(completion : Union[ChatCompletion, ChatCompletionChunk]) -> dict:
    if isinstance(completion, ChatCompletionChunk):
        isStreamed = True
    else:
        isStreamed = False
    data = {
        "choices": [ ],
        "created": completion.created,
        "id": completion.id,
        "model": completion.model,
        "object": completion.object,
        "system_fingerprint": completion.system_fingerprint,
        "usage": {
            "prompt_tokens":  None,
            "completion_tokens":  None,
            "total_tokens":  None
        }
    }
    if completion.usage:
        if completion.usage.prompt_tokens:
            data["usage"]["prompt_tokens"] = completion.usage.prompt_tokens
        if completion.usage.completion_tokens:
            data["usage"]["completion_tokens"] = completion.usage.completion_tokens
        if completion.usage.total_tokens:
            data["usage"]["total_tokens"] = completion.usage.total_tokens

    for choice in completion.choices:
        if isStreamed:
            currentKey = "delta"
            c = {
                "finish_reason": choice.finish_reason,
                "index": choice.index,
                "end_turn": choice.end_turn,
                #"logprobs": choice.logprobs,
                currentKey: {
                    "refusal": choice.delta.refusal,
                    "role": choice.delta.role,
                    "content": choice.delta.content
                    # other fields: function_call, tool_calls, audio
                }
            }
            # add context if exists
            try:
                c[currentKey]["context"] = choice.delta.context
            except:
                pass
        else:
            currentKey = "message"
            c = {
                "finish_reason": choice.finish_reason,
                "index": choice.index,
                "end_turn": choice.message.end_turn,
                #"logprobs": choice.logprobs,
                currentKey: {
                    "refusal": choice.message.refusal,
                    "role": choice.message.role,
                    "content": choice.message.content
                    # other fields: function_call, tool_calls, audio
                }
            }
            # add context if exists
            try:
                c[currentKey]["context"] = choice.message.context
            except:
                pass
        # check if context exists 
        if "context" in c[currentKey]:
            # check if itent exists and is a string
            if "intent" in c[currentKey]["context"] and isinstance(c[currentKey]["context"]["intent"], str):
                try:
                    c[currentKey]["context"]["intent"] = json.loads( c[currentKey]["context"]["intent"])
                except:
                    pass
            # check if citations exists and parse the information on pages and storage account
            if "citations" in c[currentKey]["context"] and isinstance(c[currentKey]["context"]["citations"], list):
                for citation in c[currentKey]["context"]["citations"]:
                    try:
                        citation["pages"] = re.findall(r'_pages_(\d+)', citation["filepath"] )
                        if citation["url"].lower().startswith("http"):
                            urlParts = citation["url"].split("/")
                            if len(urlParts) >= 4:
                                citation["storageaccount_name"] = urlParts[2].split(".")[0]
                                citation["storageaccount_container"] = urlParts[3]
                                citation["storageaccount_blob"] = unquote("/".join(urlParts[4:]).split("?")[0].split("#")[0])
                    except:
                        pass
        data["choices"].append(c)
    return data

class EasyChatMessage:
    role: str
    content: str
    def __init__(self, role: str, content: str):
        role = str(role).strip().lower()
        if role not in ['system', 'user', 'assistant']:
            raise ValueError("role must be 'system', 'user' or 'assistant'")
        self.role = role
        self.content = content


class EasyChatClient:
    _open_ai_client: AzureOpenAI
    _open_ai_deployment_name: str
    _open_ai_embedding_deployment_name: str
    _azure_search_api_base: str
    _azure_search_api_key: str
    _azure_search_index_name: str
    _semantic_configuration: str
    _filter: str = ""
    _system_message : str = "You are an helpful assistant that helps finding information from documents."
    _system_few_shot_examples : List[str] = [ ]
    _final_system_message : str = "You are an helpful assistant that helps finding information from documents."
    _temperature : float = 0.1
    
    def __init__(
        self,
        open_ai_client : Union[AzureOpenAI, None] = None,
        open_ai_deployment_name: Union[None, str] = None,
        open_ai_embedding_deployment_name: Union[None, str] = None,
        azure_search_api_base: Union[None, str] = None,
        azure_search_index_name: Union[None, str] = None,
        azure_search_api_key: Union[None, str] = None,
        semantic_configuration: Union[None, str] = None
    ):
        """
        Create a new EasyChatClient

        :param open_ai_client: AzureOpenAI, optional, if not set, will use default credential
        :param open_ai_deployment_name: str, optional, default is 'gpt-4o'
        :param open_ai_embedding_deployment_name: str, optional, default is 'text-embedding-ada-002'
        :param azure_search_api_base: str, required
        :param azure_search_index_name: str, optional, default is 'documents'
        :param azure_search_api_key: str, optional, if not set will use managed identity of open ai
        :returns EasyChatClient
        :raises ValueError: if azure_search_api_base or open_ai_client is not set
        """

        if isinstance(open_ai_client, AzureOpenAI):
            self._open_ai_client = open_ai_client
        else:
            if os.getenv("OPENAI_API_BASE") is None or os.getenv("OPENAI_API_BASE") == "":
                raise ValueError("OPENAI_API_BASE is required")
            if os.getenv("OPENAI_API_KEY") is None:
                self._open_ai_client = AzureOpenAI(
                    azure_endpoint = os.getenv("OPENAI_API_BASE"),
                    azure_ad_token_provider = get_bearer_token_provider(DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default"),
                    api_version = "2024-02-01"
                )
            else:
                self._open_ai_client = AzureOpenAI(
                    azure_endpoint = os.getenv("OPENAI_API_BASE"),
                    api_key = os.getenv("OPENAI_API_KEY"),
                    api_version = "2024-02-01"
                )
        
        # api_key: if none, try to get from env
        if azure_search_api_key is None:
            azure_search_api_key = os.getenv("AZURESEARCH_API_KEY")
        # api_key is optional, if not set, we use managed identity
        if azure_search_api_key is None:
            azure_search_api_key = ""
        self._azure_search_api_key = str(azure_search_api_key)

        # api_base: if none, try to get from env
        if azure_search_api_base is None:
            azure_search_api_base = os.getenv("AZURESEARCH_API_BASE")
        # api_base is required
        if azure_search_api_base is None or azure_search_api_base == "":
            raise ValueError("AZURESEARCH_API_BASE is required")
        self._azure_search_api_base = str(azure_search_api_base)

        # index_name: if none, try to get from env
        if azure_search_index_name is None:
            azure_search_index_name = os.getenv("AZURESEARCH_INDEX_NAME")
        # index_name is optional
        if azure_search_index_name is None or azure_search_index_name == "":
            azure_search_index_name = "documents"
        self._azure_search_index_name = str(azure_search_index_name)

        # open_ai_deployment_name: if none, try to get from env
        if open_ai_deployment_name is None:
            open_ai_deployment_name = os.getenv("OPENAI_DEPLOYMENT_NAME")
        # open_ai_deployment_name is optional
        if open_ai_deployment_name is None or open_ai_deployment_name == "":
            open_ai_deployment_name = "gpt-4o"
        self._open_ai_deployment_name = str(open_ai_deployment_name)

        # open_ai_embedding_deployment_name: if none, try to get from env
        if open_ai_embedding_deployment_name is None:
            open_ai_embedding_deployment_name = os.getenv("OPENAI_EMBEDDING_DEPLOYMENT_NAME")
        # open_ai_embedding_deployment_name is optional
        if open_ai_embedding_deployment_name is None or open_ai_embedding_deployment_name == "":
            open_ai_embedding_deployment_name = "text-embedding-ada-002"
        self._open_ai_embedding_deployment_name = str(open_ai_embedding_deployment_name)

        # semantic_configuration: if none, try to get from env
        if semantic_configuration is None or semantic_configuration == "":
            semantic_configuration = f"{self._azure_search_index_name}-semantic-configuration"
        self._semantic_configuration = str(semantic_configuration)


    def setTemperature(self, temperature : float):
        if temperature < 0 or temperature > 2:
            raise ValueError("Temperature must be between 0 and 2")
        self._temperature = float(temperature)

    def getTemperature(self) -> float:
        return self._temperature

    def setSearchFilterFromRole(self, role : ChatbotRole, storage_base_url : str = ""):
        f = ""
        if not (role.getFilter() is None):
            f = str(role.getFilter())
        if not (role.getBlobPathStartsWith() is None):
            if f != "":
                f += " and "
            metadataPath = storage_base_url + "/" +  quote(str(role.getBlobPathStartsWith()).lstrip("/")) + "*"
            metadataPath = metadataPath.replace("/", "\\/").replace(":", "\\:")
            f += "search.ismatch('\"" + metadataPath + "\"', 'metadata_storage_path')" 
        self._filter = f

    def setSearchFilter(self, filter : str):
        self._filter = str(filter)
    def getSearchFilter(self) -> str:
        return self._filter
    

    def _updateFinalSystemMessage(self):
        self._final_system_message = self._system_message
        if len(self._system_few_shot_examples) > 0:
            self._final_system_message += "\n\nFew-shot examples:\n" + "\n".join(self._system_few_shot_examples)
    def setFewShotExamples(self, examples: List[str]):
        self._system_few_shot_examples = examples
        self._updateFinalSystemMessage()
    def getFewShotExamples(self) -> List[str]:
        return self._system_few_shot_examples
    def setSystemMessage(self, message: str):
        self._system_message = message
        self._updateFinalSystemMessage()
    def getSystemMessage(self) -> str:
        return self._system_message

    def _chat(self, messages: List[EasyChatMessage], streamed : bool = False):
        dataSource = {
            "type": "azure_search",
            "parameters": {
                "endpoint": self._azure_search_api_base,
                "index_name": self._azure_search_index_name,
                "top_n_documents": 5,
                "role_information": "You must generate citation based on the retrieved information.",
                "fields_mapping": {
                    "filepath_field": "chunk_id",
                    "url_field": "metadata_storage_path"
                },
                "embedding_dependency": {
                    "type": "deployment_name",
                    "deployment_name": self._open_ai_embedding_deployment_name
                },
                "query_type": "vector_semantic_hybrid",
                "semantic_configuration": self._semantic_configuration
            }
        }
        # setting authentication
        if self._azure_search_api_key == "":
            dataSource["parameters"]["authentication"] = {
                "type": "system_assigned_managed_identity"
            }
        else:
            dataSource["parameters"]["authentication"] = {
                "type": "api_key",
                "api_key": self._azure_search_api_key
            }
        # setting filter
        if self._filter != "":
            dataSource["parameters"]["filter"] = str(self._filter)
        # setting messages
        msgs = [
            {
                "role": "system",
                "content": self._final_system_message
            }
        ]
        for message in messages:
            msgs.append({
                "role": message.role,
                "content": message.content
            })
        # return the completion
        return self._open_ai_client.chat.completions.create(
            model = self._open_ai_deployment_name,
            messages = msgs,
            temperature= float(self._temperature), # recommended value is 0 or close to 0 (it can be between 0 and 2)
            extra_body= {
                "data_sources": [ dataSource ]
            },
            stream=streamed
        )

    def streamedChat(self, messages: List[EasyChatMessage], outputFormat : str = "dict") -> Generator[Union[dict, str]]:
        if outputFormat == "json":
            for msg in self._chat(messages, True):
                yield (json.dumps(get_json_serializable_response(msg)) + "\n")
        elif outputFormat == "dict":
            for msg in self._chat(messages, True):
                yield get_json_serializable_response(msg)
        else:
            raise ValueError("outputFormat must be 'json' or 'dict'")

    def chat(self, messages: List[EasyChatMessage]) -> dict:       
        return get_json_serializable_response(self._chat(messages, False))


def dict_to_chat_messages(data: dict) -> List[EasyChatMessage]:
    if "messages" in data:
        return [ EasyChatMessage(message["role"], message["content"]) for message in data["messages"] ]
    return []
