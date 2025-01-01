import type {SearchServiceResponse, Index} from '../types'
import authToken from './auth-token'
import {SearchClient, AzureKeyCredential} from '@azure/search-documents'

// TODO: Replace with `playgroundUrl` from React payload instead of hard-coding here
const MODELS_ENDPOINT = 'https://models.inference.ai.azure.com'

let index: Index

export function getIndex(): Index {
  return index
}

export async function fetchIndex(): Promise<Index | null> {
  const res = await fetch(`${MODELS_ENDPOINT}/freeazuresearch/endpoint`, {
    headers: {
      Authorization: await authToken.getAuthTokenValue(),
      'Content-Type': 'application/file',
      'X-Auth-Provider': 'github',
    },
  })

  //  TODO: Handle errors properly and show on the UI
  if (!res.ok) {
    // const {error} = await res.json()
    // throw new Error(error.message)
    return null
  }

  const searchService: SearchServiceResponse = await res.json()

  if (!searchService.indexName) {
    return null
  }

  index = {
    name: searchService.indexName,
    endpoint: searchService.endpoint,
    apiKey: searchService.apiKey,
    status: searchService.indexerLastExecutionResult,
    //  TODO: Determine what searchDocsCount is in comparison to file "size"
    //  TODO: Files is returned as an empty array early in the indexing process. So changes from 0 files to n files
    files: searchService.indexStats?.files.map(({name, searchDocsCount}) => ({name, size: searchDocsCount})) ?? [],
  }

  return index
}

export async function uploadFile(uploadSession: string, file: File): Promise<void> {
  const res = await fetch(`${MODELS_ENDPOINT}/freeazuresearch/files/${uploadSession}/${file.name}`, {
    method: 'PUT',
    headers: {
      Authorization: await authToken.getAuthTokenValue(),
      'Content-Type': 'application/file',
      'X-Auth-Provider': 'github',
    },
    body: file,
  })

  //  TODO: Handle errors properly and show on the UI
  if (!res.ok) {
    // const {error} = await res.json()
    // throw new Error(error.message)
    return
  }

  return
}

export async function createUploadSession(): Promise<string> {
  const res = await fetch(`${MODELS_ENDPOINT}/freeazuresearch/files/createUploadSession`, {
    method: 'POST',
    headers: {
      Authorization: await authToken.getAuthTokenValue(),
      'Content-Type': 'application/json',
      'X-Auth-Provider': 'github',
    },
  })

  //  TODO: Handle errors properly and show on the UI
  if (!res.ok) {
    // const {error} = await res.json()
    // throw new Error(error.message)
    return ''
  }

  const {id: sessionId} = await res.json()

  return sessionId
}

export async function completeUploadSession(uploadSession: string): Promise<{id: string; indexerName: string}> {
  const res = await fetch(`${MODELS_ENDPOINT}/freeazuresearch/files/${uploadSession}/_complete`, {
    method: 'POST',
    headers: {
      Authorization: await authToken.getAuthTokenValue(),
      'Content-Type': 'application/json',
      'X-Auth-Provider': 'github',
    },
  })

  //  TODO: Handle errors properly and show on the UI
  if (!res.ok) {
    // const error = await res.text()
    // throw new Error(error)
    return {id: 'error', indexerName: 'error'}
  }

  return await res.json()
}

export async function deleteIndex(): Promise<void> {
  const res = await fetch(`${MODELS_ENDPOINT}/freeazuresearch/index`, {
    method: 'DELETE',
    headers: {
      Authorization: await authToken.getAuthTokenValue(),
      'Content-Type': 'application/json',
      'X-Auth-Provider': 'github',
    },
  })

  //  TODO: Handle errors properly and show on the UI
  if (!res.ok) {
    // const {error} = await res.json()
    // throw new Error(error.message)
  }
}

export const searchTool = {
  type: 'function',
  function: {
    name: 'search_documents',
    description: 'Search documents matching a query given as a series of keywords.',
    parameters: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'a series of keywords to use as query to search documents',
        },
      },
      required: ['query'],
    },
  },
}

export async function searchDocuments({query}: {query: string; endpoint: string; apiKey: string}): Promise<string> {
  const {endpoint, apiKey, name} = index
  if (!endpoint || !apiKey || !name) {
    throw new Error('No index selected')
  }

  const searchClient = new SearchClient(endpoint, name, new AzureKeyCredential(apiKey))
  const searchRes = await searchClient.search(query, {
    top: 5,
    queryType: 'semantic',
    select: ['chunk_id', 'title', 'chunk'],
    semanticSearchOptions: {},
    vectorSearchOptions: {
      queries: [
        {
          kind: 'text',
          text: query,
          kNearestNeighborsCount: 50,
          fields: ['text_vector'],
        },
      ],
    },
  })

  const results = []
  let result = await searchRes.results.next()
  while (!result.done) {
    const doc = result.value.document as {title: string; chunk: string}
    results.push(JSON.stringify({title: doc.title, content: doc.chunk.replaceAll('\n', ' ')}))
    result = await searchRes.results.next()
  }
  return results.join('\n')
}

// TODO: Pull this content dynamically from the sample repository
export const pythonRagCodeSnippet = `import os
import json

from azure.ai.inference import ChatCompletionsClient
from azure.core.credentials import AzureKeyCredential
from azure.ai.inference.models import *
import requests
from azure.search.documents import SearchClient
from azure.search.documents.models import QueryType, VectorizableTextQuery


# To authenticate with the model you will need to generate a personal access token (PAT) in your GitHub settings.
# Create your PAT token by following instructions here: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
MODELS_ENDPOINT = "{model_endpoint}"

client = ChatCompletionsClient(
    endpoint=MODELS_ENDPOINT,
    credential=AzureKeyCredential(GITHUB_TOKEN),
)

# Get your free RAG endpoint from GitHub Models playground
SEARCH_ENDPOINT = "{search_endpoint}"

search_client = SearchClient(
    endpoint=SEARCH_ENDPOINT,
    index_name="{search_index}",
    credential=AzureKeyCredential(GITHUB_TOKEN),
)


def search_documents(query: str):
    """Search documents matching a query given as a series of keywords."""
    # search for documents that are semantically similar to the query
    r = search_client.search(
        search_text=query,
        vector_queries=[
            VectorizableTextQuery(
                text=query, k_nearest_neighbors=50, fields="text_vector"
            )
        ],
        query_type=QueryType.SEMANTIC,
        top=5,
        select=["chunk_id", "title", "chunk"],
    )

    # create a json structure for the tool output
    results = [f"title:{doc['title']}\\n" + f"content: {doc['chunk']}".replace("\\n", " ") for doc in r]
    # return the json structure as a string
    return json.dumps(results)


search_tool = ChatCompletionsToolDefinition(
    function=FunctionDefinition(
        name=search_documents.__name__,
        description=search_documents.__doc__,
        parameters={
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "a series of keywords to use as query to search documents",
                }
            },
            "required": ["query"],
        },
    )
)

# start a loop to interact with the model
agent_returned = False
messages = [
    SystemMessage(
        content="""You are an assistant that answers users questions about documents. You are given a tool that can search within those documents. Do that systematically to provid the best answers to the user's questions. If you do not find the information, just say you do not know."""
    ),
    UserMessage(content="Can I claim an ambulance?"),]
print(f"User> {messages[-1].content}")

while not agent_returned:
    # Initialize the chat history with the assistant's welcome message
    response = client.complete(
        messages=messages,
        tools=[search_tool],
        model="{model_name}",
        temperature={temperature},
        max_tokens={max_tokens},
        top_p={top_p},
    )

    # We expect the model to ask for a tool call
    if response.choices[0].finish_reason == CompletionsFinishReason.TOOL_CALLS:
        # Append the model response to the chat history
        messages.append(
            AssistantMessage(tool_calls=response.choices[0].message.tool_calls)
        )

        # There might be multiple tool calls to run in parallel
        if response.choices[0].message.tool_calls:
            for tool_call in response.choices[0].message.tool_calls:
                # We expect the tool to be a function call
                if isinstance(tool_call, ChatCompletionsToolCall):
                    # Parse the function call arguments and call the function
                    function_args = json.loads(
                        tool_call.function.arguments.replace("'", '"')
                    )
                    print(
                        f"System> Calling function \`{tool_call.function.name}\` with arguments {function_args}"
                    )
                    callable_func = locals()[tool_call.function.name]
                    function_return = callable_func(**function_args)
                    print(f"System> Function returned.")

                    # Append the function call result to the chat history
                    messages.append(
                        ToolMessage(tool_call_id=tool_call.id, content=function_return)
                    )
                else:
                    raise ValueError(
                        f"Expected a function call tool, instead got: {tool_call}"
                    )
    else:
        agent_returned = True
        print(f"Assistant> {response.choices[0].message.content}")`
