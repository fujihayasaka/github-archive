import type {Message} from './api'
import type {Config, ModelCfg} from './config'
import {expandDatasets, type DataRow} from './dataset'
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
  for (const model of cfg.models) {
    for (const prompt of cfg.prompts) {
      const expandedPrompt = await expandPrompt(prompt)

      for (const row of await expandDatasets(cfg.datasets)) {
        const messages = expandedPrompt.map(x => replaceVarsInMessage(x, row))

        yield await runEvalForRow(model, messages, row, cfg, options, s)

        if (s?.aborted) {
          return
        }
      }
    }
  }
}

async function runEvalForRow(
  model: ModelCfg,
  messages: Message[],
  row: DataRow,
  c: Config,
  options: EvalOptions,
  s?: AbortSignal,
): Promise<ResultRow> {
  const completion = await options.api.sendMessages(model.id, model.parameters, messages, s)
  if (!completion || !completion[0]) {
    // TODO: Better error handling here, but I don't want to check this in every code path
    throw new Error('Completion is empty')
  }

  const r: ResultRow = {
    model,
    prompt: messages,
    // TODO: Eventually we should support rendering multiple messages here, only include the
    // first completion message for now
    completion: completion[0].message,
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
