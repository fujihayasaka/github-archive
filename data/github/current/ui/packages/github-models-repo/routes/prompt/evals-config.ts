import type {Config, DataRow, EvaluatorCfg} from './evals-sdk/config'
import type {PromptConfig} from './prompts'

export function buildEvalsConfig(prompts: PromptConfig[], rows: DataRow[], evaluators: EvaluatorCfg[]): Config {
  const evalsConfig: Config = {
    prompts: prompts.map((p, idx) => ({
      // Use the index as the prompt ID for now.
      id: idx,
      model: {
        id: p.model ?? '',
        parameters: p.modelParameters,
      },
      messages: p.messages,
    })),
    datasets: [
      {
        rows,
      },
    ],
    evaluators,
  }

  return evalsConfig
}
