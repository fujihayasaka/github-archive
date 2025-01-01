import {load} from 'js-yaml'
import type {Message} from './types'

export type PromptConfig = {
  path?: string
  name?: string
  description?: string
  model?: string
  modelParameters?: Record<string, unknown>
  messages: Message[]
  testData?: PromptTestData[]
  metadata?: Record<string, unknown>
}

// TODO: should this be more flexible than just a list of input/expected pairs?
// Test data from the prompt configuration
export type PromptTestData = {
  input: string
  expected: string
}

const supportedRoles = ['assistant', 'tool', 'system', 'user', 'developer'] as const
type SupportedRole = (typeof supportedRoles)[number]

export function parsePrompt(path: string, content: string): PromptConfig {
  if (path.endsWith('.md')) {
    return parseMarkdownPrompt(path, content)
  } else if (path === '') {
    return {
      messages: [],
    } as PromptConfig
  }

  throw new Error(`Unsupported prompt type: ${path}`)
}

const rolesRegExp = new RegExp(`\\s*#?(${supportedRoles.join('|')})\\s*:\\s*$`, 'im')

export function parseMarkdownPrompt(path: string, content: string): PromptConfig {
  const pc = {
    path,
  } as PromptConfig

  // Attempt to parse front matter
  const frontMatter = content.match(/^---\n([\s\S]*?)\n---/)
  const frontMatterContent = frontMatter?.[1] ?? null
  const markdownContent = content.replace(/^---\n([\s\S]*?)\n---/, '').trim()

  if (frontMatterContent) {
    const {name, description, model, model_parameters, messages, test_data, ...metadata} = load(
      frontMatterContent,
    ) as Record<string, unknown>

    // name
    if (name) {
      if (typeof name !== 'string') {
        throw new Error('Name must be a string')
      }
      pc.name = name
    }

    // description
    if (description) {
      if (typeof description !== 'string') {
        throw new Error('Description must be a string')
      }
      pc.description = description
    }

    // model
    if (model) {
      if (typeof model !== 'string') {
        throw new Error('Model must be a string')
      }
      pc.model = model
    }

    // modelParameters
    if (model_parameters) {
      if (typeof model_parameters !== 'object') {
        throw new Error('Model parameters must be an object')
      }
      pc.modelParameters = {...model_parameters}
    }

    // testData
    if (test_data) {
      if (!Array.isArray(test_data)) {
        throw new Error('Test data must be an array of PromptTestData')
      }

      pc.testData = []
      for (const [i, td] of test_data.entries()) {
        if (typeof td.input !== 'string' || typeof td.expected !== 'string') {
          throw new Error(`Test data at index ${i} must have input and expected properties that are strings`)
        }
        pc.testData.push({
          input: td.input,
          expected: td.expected,
        })
      }
    }

    // metadata
    if (metadata) {
      pc.metadata = {...metadata}
    }
  }

  // Parse messages
  const messages: Message[] = []

  const chunks = markdownContent
    .replaceAll('\r\n', '\n') // normalize line endings
    .split(rolesRegExp)
    .filter((chunk: string) => chunk.trim()) // remove empty chunks
    .map((chunk: string) => chunk.replace(/(^\n+|\n+$)/g, '')) // remove leading/trailing newlines
  if (chunks.length > 0) {
    const roleChunk = chunks[0]!

    // If the first chunk is not a role, treat it as a user message
    if (!supportedRoles.includes(roleChunk.trim().toLowerCase() as SupportedRole)) {
      // TODO: Think about this.. do we want user or system as default?
      chunks.unshift('user')
    }

    // Remove any trailing roles with no content
    if (supportedRoles.includes(chunks[chunks.length - 1]!.trim().toLowerCase() as SupportedRole)) {
      chunks.pop()
    }

    if (chunks.length % 2 !== 0) {
      throw new Error('Invalid prompt format')
    }

    for (let i = 0; i < chunks.length; i += 2) {
      const role = chunks[i]!.trim().toLowerCase() as SupportedRole
      const messageContent = chunks[i + 1]!.trim()

      messages.push({timestamp: new Date(), role, message: messageContent})
    }
  }

  // If we didn't match any roles, but we have content, treat it as a user message
  if (messages.length === 0 && markdownContent) {
    messages.push({
      timestamp: new Date(),
      role: 'user',
      message: markdownContent,
    })
  }

  if (messages.length > 0) {
    pc.messages = messages
  }

  return pc
}
