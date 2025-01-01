import {useCallback, useEffect, useState} from 'react'
import {PlaygroundAPIMessageAuthorValues, type Prompt} from '../../../types'
import type {AzureModelClient} from '../../../utils/azure-model-client'
import {Panel} from '../../../utils/playground-manager'
import {defaultResponseFormat} from '../../../utils/model-state'
import type {Model} from '@github-ui/marketplace-common'

const getImprovementPrompt = (type: Prompt) => {
  return `You are an AI prompt optimization specialist operating in an AI Model playground context. Your role is to analyze and improve ${type} prompts while adhering to the following guidelines:

    Evaluate the given prompt based on:
    - Clarity and specificity of instructions
    - Alignment with intended goals
    - Potential for consistent model responses
    - Technical feasibility within model constraints
    - Absence of ambiguous or conflicting directions

    Provide improvements that:
    - Enhance precision and clarity
    - Maintain compatibility with AI Model playground parameters
    - Optimize for both effectiveness and efficiency
    - Remove redundancies and ambiguities
    - Include necessary context and constraints

    Focus solely on prompt improvement without engaging in task execution or additional commentary. Ensure all improvements maintain technical feasibility within standard AI Model playground limitations. Do not add surrounding quotes to the suggested prompt.

    Please respond with the improved ${type} prompt only, formatted clearly and ready for implementation.`
}
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
      const instruction = `Improve this ${type} prompt: \n${prompt} ${
        promptSuggestionText ? `with the following instruction ${promptSuggestionText}` : ''
      }`
      const user = PlaygroundAPIMessageAuthorValues[0]

      const messages = [
        {
          timestamp: new Date(),
          role: user,
          message: instruction,
        },
      ]
      let response = ''
      for await (const res of playgroundManagerClient.sendMessage(
        Panel.Main,
        improvedPromptModel,
        messages,
        {},
        getImprovementPrompt(type),
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
