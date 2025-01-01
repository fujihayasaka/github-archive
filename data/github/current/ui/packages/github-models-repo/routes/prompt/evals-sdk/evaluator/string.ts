import type {EvaluationResult, Message} from '../../types'
import type {DataRow, EvaluatorString} from '../config'
import {replaceVars} from '../variables'
import type {Evaluator} from './evaluator'

export class StringEvaluator implements Evaluator {
  private operationName: string
  private operation: (input: string, value: string) => boolean
  private value: string

  private customName: string
  private cfg: EvaluatorString

  constructor(customName: string, cfg: EvaluatorString) {
    this.customName = customName
    this.cfg = cfg

    switch (true) {
      case this.cfg.contains !== undefined:
        if (this.cfg.strict === true) {
          this.operation = (input: string, value: string) => input.includes(value)
        } else {
          /*
          TODO: To lowercase both input, and value _could_ be expensive. When we do the regex support pass,
          prefer: new RegExp(value, 'i').test(input)
          but beware, the user may want to test `1+2`, which would be /1+2/ as in `112` would match.
          As such we need to RegExp.escape, which is sadly not supported in Node, so RIP tests.
          So let's follow up.
          */
          this.operation = (input: string, value: string) => input.toLowerCase().includes(value.toLowerCase())
        }
        this.operationName = 'contains'
        this.value = this.cfg.contains!
        break

      case this.cfg.startsWith !== undefined:
        this.operation = (input: string, value: string) => input.startsWith(value)
        this.operationName = 'startsWith'
        this.value = this.cfg.startsWith!
        break

      case this.cfg.endsWith !== undefined:
        this.operation = (input: string, value: string) => input.endsWith(value)
        this.operationName = 'endsWith'
        this.value = this.cfg.endsWith!
        break

      default:
        throw new Error('unknown operation')
    }
  }

  get name(): string {
    return this.customName || `string.${this.operationName}`
  }

  async evaluate(_prompt: Message[], completion: Message, row: DataRow): Promise<EvaluationResult> {
    const value = replaceVars(this.value, row)
    const result = this.operation(completion.message, value)

    return {
      pass: result,
    }
  }
}
