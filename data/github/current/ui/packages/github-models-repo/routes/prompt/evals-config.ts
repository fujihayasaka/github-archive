import type {RepoModel} from '../../types'
import type {Config, DataRow, EvaluatorCfg} from './evals-sdk/config'
import {findModel} from './models'
import type {PromptConfig} from './prompts'

export function buildEvalsConfig(
  prompts: PromptConfig[],
  rows: DataRow[],
  evaluators: EvaluatorCfg[],
  models: RepoModel[],
): Config {
  const evalsConfig: Config = {
    prompts: prompts.map((p, idx) => {
      const model = p.model ? findModel(p.model, models) : undefined
      const messages = p.messages.filter(m => {
        if (m.role === 'system' && !model?.capabilities?.systemPrompt) {
          return false
        }
        return true
      })

      return {
        id: idx,
        model: {
          id: p.model ?? '',
          parameters: p.modelParameters,
        },
        messages,
      }
    }),
    datasets: [
      {
        rows,
      },
    ],
    evaluators,
  }

  return evalsConfig
}
