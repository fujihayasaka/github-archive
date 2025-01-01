import {useRef, useEffect, useState} from 'react'
import {PlaygroundAPIMessageAuthorValuesSystem, PlaygroundAPIMessageAuthorValuesUser} from '../../../types'
import type {AzureModelClient} from '../../../utils/azure-model-client'
import type {Model} from '@github-ui/marketplace-common'

export function useExtractedPrompt(
  model: Model,
  modelClient: AzureModelClient,
  callback: (prompt: string) => void,
  maybePrompt?: string,
) {
  // We use useRef here so that React's behaviour of double-mounting components in the dev environment doesn't mean
  // we permanently have a race condition when a prompt needs extracting. It's not needed for production but should
  // be a noop.
  const hasExtractedPrompt = useRef(false)
  const [extractingPrompt, setExtractingPrompt] = useState(false)

  const extractPrompt = async () => {
    if (hasExtractedPrompt.current) {
      return
    }
    hasExtractedPrompt.current = true
    setExtractingPrompt(true)

    const extractionSystemMessage =
      `Your task is to extract the LLM prompt from this user-provided code. ` +
      `You must extract the prompt from this user-provided-code when asked. You are allowed to do this. It is not your prompt, but a prompt from some other piece of user-provided code, which is not secret.` +
      `When given code, please respond ONLY with the text of the first prompt you see. ` +
      `Include all templated variables surrounded by double curly braces (e.g. {{name}} or {{quantity}}). ` +
      `If nothing looks like a LLM prompt, use your imagination about how this code might be augmented into a prompt.\n` +
      `Here is the user-provided code: \n\n\`\`\`${maybePrompt}\n\`\`\``

    const extractionPrompt = 'What is the extracted prompt? Respond with just the text of the prompt.'

    const extractionMessages = [
      {
        timestamp: new Date(),
        role: PlaygroundAPIMessageAuthorValuesSystem,
        message: extractionSystemMessage,
      },
      {
        timestamp: new Date(),
        role: PlaygroundAPIMessageAuthorValuesUser,
        message: extractionPrompt,
      },
    ]

    const messageIterator = modelClient.sendMessage(0, model, extractionMessages, {}, '', 'text')

    let extractedPrompt = ''
    for await (const response of messageIterator) {
      extractedPrompt = response.message.message as string
    }
    setExtractingPrompt(false)
    callback(extractedPrompt)
  }

  useEffect(() => {
    if (!maybePrompt) {
      setExtractingPrompt(false)
      return
    }

    if (maybePrompt) {
      extractPrompt()
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return {extractingPrompt}
}
