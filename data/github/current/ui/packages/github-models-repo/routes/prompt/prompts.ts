import {dump, load} from 'js-yaml'
import type {InferType} from 'yup'
import {array, date, lazy, object, string} from 'yup'
import type {RepoModel} from '../../types'
import type {EvaluatorCfg} from './evals-sdk/config'
import {EvaluatorTemplates} from './evaluators'
import {findModel, promptModelIdentifierFor} from './models'
import type {Message, MessageContent, MessageRole} from './types'

const evaluatorSchema = lazy(value => {
  switch (typeof value) {
    case 'string':
      return string().required()
    case 'object':
      return object().required()
    default:
      return object()
  }
})

const promptSchema = object({
  path: string().optional(),
  name: string().optional(),
  description: string().optional(),
  model: string().optional(),
  modelParameters: object().optional(),
  messages: array(
    object({
      role: string().oneOf(['assistant', 'tool', 'system', 'user', 'developer', 'error']).required(),
      content: string().ensure(),
      timestamp: date().required(),
    }),
  ).required(),
  responseFormat: string().oneOf(['text', 'json_object', 'json_schema']).optional(),
  jsonSchema: string().optional(),
  testData: array(
    object().test('has-string-properties', 'testData items must have string properties', function (value) {
      if (!value || typeof value !== 'object') return false
      return Object.values(value).every(v => typeof v === 'string')
    }),
  )
    .nullable()
    .optional(),
  evaluators: array().of(evaluatorSchema).optional().nullable(),
})

// Our prompt file schema wants to use message.content, but our existing codebase largely used message.message so this
// differentiates the two types.
type PromptSchema = InferType<typeof promptSchema>
export type PromptConfig = Omit<PromptSchema, 'messages' | 'evaluators'> & {
  messages: Message[]
  evaluators?: EvaluatorState[]
}
export type ActivePrompt = PromptConfig
export type PromptCollection = PromptConfig[] | [PromptConfig, ...PromptConfig[]]
export type PromptYamlConfig = Omit<PromptSchema, 'messages'> & {
  messages: Array<{
    role: 'assistant' | 'tool' | 'system' | 'user' | 'developer' | 'error'
    content: string
  }>
}

export type EvaluatorState = {
  config: EvaluatorCfg

  // Some evaluators cannot be edited. If this was added from a built-in configuration, for example, it cannot be edited.
  readonly?: boolean // default: false
}

export function parsePrompt(path: string, content: string): PromptConfig {
  const isYaml = path.endsWith('.yml') || path.endsWith('.yaml')
  const isNew = !isYaml && path === ''

  if (isYaml || isNew) {
    const yamlPrompt = isYaml ? parseYamlPrompt(path, content) : {}
    const newPrompt = isNew ? demoPrompt() : {}

    const prompt = {...yamlPrompt, ...newPrompt}
    const promptWithMessages = {
      ...prompt,
      messages: prompt?.messages ?? [],
    }

    promptSchema.validateSync(promptWithMessages, {strict: true})

    return promptWithMessages
  } else {
    throw new Error(`Unsupported prompt type: ${path}`)
  }
}

const demoPrompt = (): Partial<PromptConfig> => ({
  // By default, we want to populate the messages with a system and user message
  // This is to ensure that the user has a place to enter their prompt
  messages: [getSystemMessage(''), getUserMessage('')],
})

export function parseYamlPrompt(path: string, content: string): PromptConfig {
  const parsedPrompt = load(content) as Record<string, unknown>
  const pc: PromptConfig = {
    ...parsedPrompt,
    path,
    messages: [],
  }

  if (Array.isArray(parsedPrompt?.messages)) {
    pc.messages = parsedPrompt.messages?.map(({content: message, ...rest}) => {
      return {
        ...rest,
        message,
        timestamp: new Date(),
      } as Message
    })
  }

  // Ensure at least one system and user prompt exists
  if (!pc.messages.some(msg => msg.role === 'system')) {
    pc.messages.unshift({
      timestamp: new Date(),
      role: 'system',
      message: '',
    })
  }
  if (!pc.messages.some(msg => msg.role === 'user')) {
    pc.messages.push({
      timestamp: new Date(),
      role: 'user',
      message: '',
    })
  }

  if (Array.isArray(parsedPrompt?.evaluators)) {
    const parsedEvaluators = parsedPrompt.evaluators
      .map(evaluator => {
        if (typeof evaluator === 'string') {
          evaluator = EvaluatorTemplates.find(template => template.configTemplate.uses === evaluator)
          if (!evaluator?.configTemplate) {
            return undefined
          }
          return {config: evaluator.configTemplate, readonly: true} // TODO: raise some kind of "we couldn't find your evaluator" error for the user?
        }

        return {config: evaluator}
      })
      .filter(Boolean)
    pc.evaluators = parsedEvaluators.filter(x => x !== undefined)
  }

  return pc
}

export function promptToYaml(pc: PromptConfig, models: RepoModel[]): string {
  const {path, ...rest} = pc

  const model = findModel(pc.model ?? '', models)
  if (model) {
    rest.model = promptModelIdentifierFor(model).toLowerCase()
  }

  const promptObject: PromptYamlConfig = {
    ...rest,
    messages: rest.messages.map(({message: content, role}) => ({
      role,
      content,
      // We don't want to serialize the timestamp, as it's not part of the YAML spec
      // and we don't want to include it in the YAML output
    })),
  }

  if (rest.evaluators) {
    promptObject.evaluators = rest.evaluators?.map(evaluator => evaluator.config)
  }

  return dump(promptObject)
}

export const promptPathSeparator = '/'

export function promptPathSegments(prompt: PromptConfig) {
  const path = prompt.path || ''
  return path.split(promptPathSeparator)
}

export function doesPromptHaveFilename(prompt: PromptConfig | undefined) {
  if (!prompt) return false

  const filename = promptPathSegments(prompt).pop()
  if (!filename) return false

  return filename.trim().length > 0
}

export function isPromptComparePage(pathname: string) {
  return pathname.includes('models/prompt/compare')
}

export const getPromptMessage = (role: MessageRole, content: MessageContent): Message => ({
  role,
  message: content,
  timestamp: new Date(),
})

export const getUserMessage = (content: MessageContent): Message => getPromptMessage('user', content)
export const getSystemMessage = (content: MessageContent): Message => getPromptMessage('system', content)
