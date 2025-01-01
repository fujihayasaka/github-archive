import type {Message} from './api'

export type PromptCfg = {
  id?: number

  // TODO: CS: Explode this into individual fields?
  model: ModelCfg

  /** Define a prompt inline. This will be expanded into a single role: 'user' message */
  prompt?: string

  /** Messages to be sent */
  messages?: Message[]
}

export type PromptProcess = {
  cwd?: string

  cmd: string
}

export type DataRow = {id: number | string} & {
  [key: string]: string
}

export type Dataset =
  | {
      rows: DataRow[]
    }
  | {
      url: string
    }

export type Choice = {
  choice: string
  score: number
}

// For now, re-use the marketplace/models configuration for a model
export type ModelCfg = {
  id: string
  parameters?: Record<string, unknown>
}

export type EvaluatorLLM = {
  /**
   * Model to use when prompting. Matches via startsWith. If multiple models
   * match, the first one will be used.
   *
   * For example, if the config is:
   * > modelId: 'azureml://registries/azure-openai/models/gpt-4o'
   * and the model catalog contains:
   * - azureml://registries/azure-openai/models/gpt-4o/versions/2024-08-06
   * - azureml://registries/azure-openai/models/gpt-4o/versions/2024-11-20
   * then azureml://registries/azure-openai/models/gpt-4o/versions/2024-11-20 will be used.
   * */
  modelId: string

  /** Parameters to use when propmting model */
  modelParameters?: Record<string, unknown>

  /** Prompt to use when prompting the model. Supports variables */
  prompt: string

  /** System prompt to use when prompting the model */
  systemPrompt?: string

  /** Choices */
  choices: Choice[]
}

export type EvaluatorFunc = {
  js?: string
}

/** Built-in evaluator for simple string operations */
export type EvaluatorString = {
  startsWith?: string
  endsWith?: string
  contains?: string
}

export type EvaluatorCfg = {
  name: string

  /** Reference an existing evaluator */
  uses?: string

  llm?: EvaluatorLLM

  func?: EvaluatorFunc

  string?: EvaluatorString
}

export type Config = {
  /**
   * Prompts to evaluate.
   */
  prompts: PromptCfg[]

  /**
   * Datasets
   */
  datasets: Dataset[]

  /**
   * Tests to perform for each prompt and row in the datasets
   */
  evaluators: EvaluatorCfg[]
}
