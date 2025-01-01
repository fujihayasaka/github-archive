import type {ModelState} from '../../types'
import {createSystemMessage, createUserMessage} from '../../utils/message-content-helper'
import {validateSystemPrompt} from '../../utils/model-state'
import type {Message} from './evals-sdk/api'
import type {Config, EvaluatorCfg, DataRow} from './evals-sdk/config'

export function buildEvalsConfig(
  model: ModelState,
  systemPrompt: string | undefined,
  prompt: string,
  rows: DataRow[],
  evaluators: EvaluatorCfg[],
): Config {
  const messages: Message[] = []

  if (systemPrompt) {
    const systemMessageContent = validateSystemPrompt(model.modelInputSchema, systemPrompt)
    if (systemMessageContent) {
      messages.push(createSystemMessage(systemMessageContent) as Message)
    }
  }

  messages.push(createUserMessage(prompt) as Message)

  const evalsConfig: Config = {
    models: [
      {
        id: model.catalogData.id,
        parameters: model.parameters,
      },
    ],
    prompts: [
      {
        messages,
      },
    ],
    datasets: [
      {
        rows: rows.map(({id, ...row}) => ({
          ...row,
        })),
      },
    ],
    evaluators,
  }

  return evalsConfig
}
