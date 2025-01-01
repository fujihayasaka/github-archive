import {PlusIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {useCallback} from 'react'
import type {Message} from '../evals-sdk/api'
import {PromptAutocompleteInput} from './PromptAutocompleteInput'

export type PromptMessageEditor = {
  messages: Message[]
  updateMessages: (messages: Message[]) => void
}

export function PromptMessageEditor({messages, updateMessages}: PromptMessageEditor) {
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

  return (
    <>
      {messages.map((message, index) => (
        // Allow use of index as key in addition to timestamp
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <div key={`${message.timestamp}-${index}`} className="mb-1">
          <PromptAutocompleteInput
            label={message.role}
            prompt={message.message}
            textareaPlaceholder="Enter the task or question for the model. Example: 'Write me a song about GitHub.' Use {{variable}} for placeholders."
            setPromptInput={newPrompt => updatePromptInput(index, newPrompt)}
            variableKeys={variables}
          />
        </div>
      ))}
      <Button className="flex-self-start my-3" leadingVisual={PlusIcon}>
        Add message pair
      </Button>
    </>
  )
}
