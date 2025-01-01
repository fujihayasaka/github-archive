import type {TokenUsage} from '@github-ui/github-models'
import type {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import {useCallback, useMemo, useState} from 'react'
import {usePromptCompareManager} from '../prompt-compare-manager'
import {referencedVariablesInPrompt, replaceVarsInMessages} from '../variables'
import useActivePrompt from './use-active-prompt'
import useActivePromptModel from './use-active-prompt-model'
import {extractMessagePairs} from '../utils/message-utils'

export default function usePromptRunButton(
  modelClient: AzureModelClient,
  setShowRunVariablesDialog: (isOpen: boolean) => void,
) {
  const activePrompt = useActivePrompt()
  const model = useActivePromptModel()
  const manager = usePromptCompareManager()

  const canRun = useMemo(() => {
    return (
      activePrompt &&
      !!activePrompt.model &&
      activePrompt.messages &&
      activePrompt.messages?.length > 0 &&
      activePrompt.messages.some((x: {message?: string}) => x.message?.trim() !== '')
    )
  }, [activePrompt])

  const referencedVariables = useMemo(() => new Set<string>(referencedVariablesInPrompt(activePrompt)), [activePrompt])
  const [tokenUsage, setTokenUsage] = useState<TokenUsage | undefined>(undefined)

  const handleRun = useCallback(
    (vars: Record<string, string>) => {
      setTokenUsage(undefined)
      if (!model) {
        // Running is only enabled if we have a model, check again just to be sure (and to make TS happy)
        return
      }

      const variablesWithoutValue = Array.from(referencedVariables.keys()).filter(v => !vars[v])
      if (variablesWithoutValue.length > 0) {
        // One of the referenced variables doesn't have a value, ask the user for a value first, do not run the prompt.
        setShowRunVariablesDialog(true)
        return
      }

      const expandedPrompt = replaceVarsInMessages(activePrompt.messages, vars)

      const systemPrompt = expandedPrompt.find(x => x.role === 'system')?.message ?? ''
      const userPrompt = expandedPrompt.find(x => x.role === 'user')?.message ?? ''
      const expandedMessagePairs = extractMessagePairs(expandedPrompt)

      const {modelParameters, responseFormat, jsonSchema} = activePrompt

      manager.sendMessage(
        model,
        modelClient,
        systemPrompt,
        userPrompt,
        modelParameters,
        setTokenUsage,
        expandedMessagePairs,
        responseFormat,
        jsonSchema,
      )
    },
    [activePrompt, manager, model, modelClient, referencedVariables, setShowRunVariablesDialog],
  )

  const handleStop = useCallback(() => {
    modelClient.stopStreamingMessages(0)
  }, [modelClient])

  return {
    canRun,
    handleRun,
    handleStop,
    tokenUsage,
    setTokenUsage,
  }
}
