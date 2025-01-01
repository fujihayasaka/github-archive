import {useCallback} from 'react'
import type {RepoModel} from '../../../types'
import type {Message} from '../types'
import {PromptAutocompleteInput} from './PromptAutocompleteInput'
import {messageLabel} from '../utils/message-utils'

export type PromptMessageEditor = {
  selectedModel: RepoModel | undefined
  messages: Message[]
  updateMessages: (messages: Message[]) => void
}

export function PromptMessageEditor({selectedModel, messages, updateMessages}: PromptMessageEditor) {
  const variables: string[] = []

  const updatePromptInput = useCallback(
    (index: number, newPrompt: string) => {
      updateMessages([
        ...messages.slice(0, index),
        {
          ...messages[index],
          message: newPrompt,
        } as Message,
        ...messages.slice(index + 1),
      ])
    },
    [messages, updateMessages],
  )

  const placeholders = {
    system: "Define the model's behavior or role. Example: 'You are a spaceship captain telling intergalactic tales.'",
    user: "Enter the task or question for the model. Example: 'Write me a song about GitHub.' Use {{variable_name}} for placeholders.",
    assistant: '',
    tool: '',
    developer: '',
    error: '',
  }

  // In this component we only want to render up to and including the first user message.
  // Other messages will be rendered by <PromptMessagePair>
  const indexOfFirstUserMessage = messages.findIndex(m => m.role === 'user')

  return (
    <>
      {messages.slice(0, indexOfFirstUserMessage + 1).map((message, index) => {
        const disableSystemPrompt = message.role === 'system' && !selectedModel?.capabilities?.systemPrompt
        return (
          // Allow use of index as key in addition to timestamp
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <div key={`${message.timestamp}-${index}`} className="mb-3">
            <PromptAutocompleteInput
              label={messageLabel(message.role)}
              prompt={message.message}
              textareaPlaceholder={placeholders[message.role]}
              setPromptInput={newPrompt => updatePromptInput(index, newPrompt)}
              variableKeys={variables}
              disabled={disableSystemPrompt}
              disabledMessage="The selected model does not support system prompts. Value will not be applied."
            />
          </div>
        )
      })}
    </>
  )
}
