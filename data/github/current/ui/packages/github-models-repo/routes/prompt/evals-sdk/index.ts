import type {Config, DataRow, PromptCfg} from './config'
import {expandDatasets} from './dataset'
import {getEvaluator} from './evaluator/provider'
import type {EvalOptions} from './options'
import {expandPrompt} from './prompt'
import type {ResultRow} from './result'
import {replaceVarsInMessage} from './variables'

export async function* runEval(
  cfg: Config,
  options: EvalOptions,
  s?: AbortSignal,
): AsyncGenerator<ResultRow, void, unknown> {
  for (const row of await expandDatasets(cfg.datasets)) {
    for (const prompt of cfg.prompts) {
      yield await runEvalForRow(prompt, row, cfg, options, s)

      if (s?.aborted) {
        return
      }
    }
  }
}

async function runEvalForRow(
  prompt: PromptCfg,
  row: DataRow,
  c: Config,
  options: EvalOptions,
  s?: AbortSignal,
): Promise<ResultRow> {
  const model = prompt.model

  // Expand prompt into messages
  const promptMessages = await expandPrompt(prompt)

  // Expand the prompt with the variables from the data set row
  const messages = promptMessages.map(x => replaceVarsInMessage(x, row))

  const completion = await options.api.sendMessages(model.id, model.parameters, messages, s)
  if (!completion || !completion[0]) {
    // TODO: Better error handling here, but I don't want to check this in every code path
    throw new Error('Completion is empty')
  }

  const r: ResultRow = {
    prompt,
    messages,
    completions: completion,
    data: row,
    evals: [],
  }

  // Run each evaluator on the completion
  for (const e of c.evaluators) {
    const evaluator = await getEvaluator(e, options)
    const evalResult = await evaluator.evaluate(messages, completion[0], row, s)

    r.evals.push(evalResult)

    if (s?.aborted) {
      break
    }
  }

  return r
}
