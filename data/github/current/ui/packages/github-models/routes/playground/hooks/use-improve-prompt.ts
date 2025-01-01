import {useCallback, useEffect, useState} from 'react'
import type {Prompt} from '../../../types'
import type {AzureModelClient} from '../../../utils/azure-model-client'
import {Panel} from '../../../utils/playground-manager'
import {defaultResponseFormat} from '../../../utils/model-state'
import type {Model} from '@github-ui/marketplace-common'
import promptTemplate from '../../../prompts/improve-prompt.prompt.yml'

export function useImprovePrompt(
  prompt: string,
  promptSuggestionText: string,
  playgroundManagerClient: AzureModelClient,
  improvedPromptModel: Model,
  type: Prompt,
) {
  const [generatedPrompt, setGeneratedPrompt] = useState(prompt)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState(false)
  const generatePrompt = useCallback(async () => {
    try {
      const messages = promptTemplate.messages.map(message => ({
        timestamp: new Date(),
        role: message.role,
        message: message.content
          .replace('{{type}}', type)
          .replace('{{prompt}}', prompt)
          .replace('{{promptSuggestionText}}', promptSuggestionText),
      }))

      let response = ''
      for await (const res of playgroundManagerClient.sendMessage(
        Panel.Main,
        improvedPromptModel,
        messages,
        {},
        null,
        defaultResponseFormat,
      )) {
        response = res.message.message as string
      }
      setGeneratedPrompt(response)
    } catch {
      setError(true)
    } finally {
      setIsLoading(false)
    }
  }, [type, prompt, promptSuggestionText, playgroundManagerClient, improvedPromptModel])

  useEffect(() => {
    generatePrompt()
  }, [generatePrompt])

  return {generatedPrompt, isLoading, error}
}
