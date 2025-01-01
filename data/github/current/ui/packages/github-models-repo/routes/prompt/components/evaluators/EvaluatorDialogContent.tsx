import type {Dispatch, SetStateAction} from 'react'
import type {EvaluatorCfg} from '../../evals-sdk/config'
import {LLMEvaluatorContent} from './LLMEvaluatorContent'
import {StringCheckContent} from './StringCheckContent'

interface EvaluatorDialogContentProps {
  config: EvaluatorCfg
  readonly: boolean
  setConfig: Dispatch<SetStateAction<EvaluatorCfg>>
}

export function EvaluatorDialogContent({config, readonly, setConfig}: EvaluatorDialogContentProps) {
  if (config.string) {
    return (
      <StringCheckContent
        e={config.string}
        readonly={readonly}
        updateEvaluator={e => {
          setConfig({
            ...config,
            string: e,
          })
        }}
      />
    )
  }

  if (config.llm) {
    return (
      <LLMEvaluatorContent
        e={config.llm}
        readonly={readonly}
        updateEvaluator={e => {
          setConfig({
            ...config,
            llm: e,
          })
        }}
      />
    )
  }

  return null
}
