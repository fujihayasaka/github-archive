import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import type {z} from 'zod'
import {zodTypeToJSONSchema} from './zod-to-json-schema'
import {Streamer} from './streamer'
import type {CAPIMessage, CAPIResponse} from './types'

export async function streamText(
  url: string,
  model: string,
  prompt: string,
  streamCallback: (chunk: string) => void,
  system?: string,
  temperature?: number,
): Promise<void> {
  const stream = await getStream(url, model, prompt, system, temperature)
  for await (const chunk of stream) {
    const content = chunk.choices[0]?.delta?.content
    if (!content) {
      continue
    }
    streamCallback(content)
  }
}

export async function getStream(url: string, model: string, prompt: string, system?: string, temperature?: number) {
  const copilotAuthTokenProvider = new CopilotAuthTokenProvider([])
  const token = await copilotAuthTokenProvider.getAuthToken()
  const basePath = url
  const headers: {[key: string]: string} = {
    Authorization: token.authorizationHeaderValue,
    'copilot-integration-id': 'playground-dev',
    'Content-Type': 'application/json',
  }

  const messages: CAPIMessage[] = []
  if (system) {
    messages.push({
      role: 'system',
      content: system,
    })
  }

  messages.push({
    role: 'user',
    content: prompt,
  })

  const body = {
    messages,
    model,
    temperature: temperature || 1.0,
    stream: true,
  }

  const signal = null
  const res = await fetch(`${basePath}/chat/completions`, {
    method: 'POST',
    mode: 'cors',
    cache: 'no-cache',
    headers,
    body: JSON.stringify(body),
    signal,
  })

  const reader = res.body?.getReader()

  if (!reader) {
    throw new Error('No reader available')
  }

  const streamer = new Streamer(reader)
  const stream = streamer.stream()
  return stream
}

export async function generateText(
  url: string,
  model: string,
  prompt: string,
  system?: string,
  temperature?: number,
): Promise<string> {
  // this.copilotAuthTokenProvider = new CopilotAuthTokenProvider(ssoOrgs.map(org => org.id))
  const copilotAuthTokenProvider = new CopilotAuthTokenProvider([])
  const token = await copilotAuthTokenProvider.getAuthToken()
  const basePath = url
  const headers: {[key: string]: string} = {
    Authorization: token.authorizationHeaderValue,
    'copilot-integration-id': 'playground-dev',
    'Content-Type': 'application/json',
  }

  const messages: CAPIMessage[] = []
  if (system) {
    messages.push({
      role: 'system',
      content: system,
    })
  }

  messages.push({
    role: 'user',
    content: prompt,
  })

  const body = {
    messages,
    model,
    temperature: temperature || 1.0,
  }

  const signal = null
  const res = await fetch(`${basePath}/chat/completions`, {
    method: 'POST',
    mode: 'cors',
    cache: 'no-cache',
    headers,
    body: JSON.stringify(body),
    signal,
  })

  const choices = (await res.json()) as CAPIResponse
  const messageContent = choices.choices?.[0]?.message?.content
  if (!messageContent) {
    throw new Error('Missing message content in API response')
  }
  return messageContent
}

export async function generateObject<OBJECT>(
  url: string,
  model: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  schema: z.Schema<OBJECT, z.ZodTypeDef, any>,
  system: string,
  prompt: string,
  temperature: number,
): Promise<OBJECT> {
  const copilotAuthTokenProvider = new CopilotAuthTokenProvider([])
  const token = await copilotAuthTokenProvider.getAuthToken()
  const basePath = url
  const headers: {[key: string]: string} = {
    Authorization: token.authorizationHeaderValue,
    'copilot-integration-id': 'hypersight-prototype',
    'Content-Type': 'application/json',
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const jsonSchema = zodTypeToJSONSchema(schema as any)

  const body = {
    messages: [
      {
        role: 'system',
        content: `Generate a JSON object that strictly adheres to the following schema, without including the schema text itself: ${JSON.stringify(
          jsonSchema,
        )}\n\n${system}`,
      },
      {
        role: 'user',
        content: prompt,
      },
    ],
    model,
    response_format: {type: 'json_object'},
    temperature,
  }

  const signal = null
  const res = await fetch(`${basePath}/chat/completions`, {
    method: 'POST',
    mode: 'cors',
    cache: 'no-cache',
    headers,
    body: JSON.stringify(body),
    signal,
  })

  const res2 = (await res.json()) as CAPIResponse
  const messageContent = res2.choices?.[0]?.message?.content
  if (!messageContent) {
    throw new Error('Missing message content in API response')
  }
  const jsonContent: unknown = JSON.parse(messageContent)
  const parsedObj = schema.safeParse(jsonContent)
  if (!parsedObj.success) {
    throw new Error(`Invalid object: ${JSON.stringify(parsedObj.error.format())}`)
  }
  const obj = parsedObj.data
  return obj
}
