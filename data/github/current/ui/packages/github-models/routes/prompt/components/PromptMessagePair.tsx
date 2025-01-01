import {PlusIcon, TrashIcon} from '@primer/octicons-react'
import {Button, IconButton, Label, Tooltip} from '@primer/react'
import styles from './PromptMessagePair.module.css'
import type {MessagePair} from '../../../types'
import {PromptAutocompleteInput} from './PromptAutocompleteInput'
import {testIdProps} from '@github-ui/test-id-props'

export type PromptMessagePairProps = {
  messagePairs: MessagePair[]
  setMessagePairs: (messagePairs: MessagePair[]) => void
  variableKeys: string[]
}

export const messagePairLimit = 4

export function PromptMessagePair({messagePairs, setMessagePairs, variableKeys}: PromptMessagePairProps) {
  const handleAddingMessagePair = () => {
    setMessagePairs([...messagePairs, {assistant: '', user: ''}])
  }

  const handleUpdatingUserPrompt = (userPrompt: string, index: number) => {
    setMessagePairs(messagePairs.map((pair, i) => (i === index ? {...pair, user: userPrompt} : pair)))
  }

  const handlingUpdatingAssistantPrompt = (assistantPrompt: string, index: number) => {
    setMessagePairs(messagePairs.map((pair, i) => (i === index ? {...pair, assistant: assistantPrompt} : pair)))
  }

  const handleRemoveMessagePair = (index: number) => {
    setMessagePairs(messagePairs.filter((_, i) => i !== index))
  }

  const divKey = (index: number) => `message-pair-${index}`

  return (
    <div>
      {messagePairs.map((pair, index) => (
        <div className={styles.messagePair} key={divKey(index)}>
          <div className={styles.pairHeader}>
            <Label variant="accent" size="large">
              Pair {index + 1}
            </Label>
            <IconButton
              size="small"
              icon={TrashIcon}
              variant="danger"
              aria-label={`Remove message pair ${index + 1}`}
              onClick={() => handleRemoveMessagePair(index)}
              {...testIdProps(`remove-message-pair-${index}`)}
            />
          </div>
          <div className="mb-3">
            <PromptAutocompleteInput
              label="Assistant"
              prompt={pair.assistant}
              setPromptInput={input => handlingUpdatingAssistantPrompt(input, index)}
              variableKeys={variableKeys}
              textareaPlaceholder="Define how the model should reply. This response, along with the previous user prompt, will shape the next interaction."
            />
          </div>
          <div className="mb-3">
            <PromptAutocompleteInput
              label="User"
              prompt={pair.user}
              setPromptInput={prompt => handleUpdatingUserPrompt(prompt, index)}
              variableKeys={variableKeys}
              textareaPlaceholder="Ask the model something. The previous responses will be considered. You can also use {{input}}."
            />
          </div>
        </div>
      ))}
      {messagePairs.length < messagePairLimit ? (
        <Button size="small" leadingVisual={PlusIcon} onClick={handleAddingMessagePair}>
          Add message pair
        </Button>
      ) : (
        <Tooltip text="You can only have up to 4 message pairs" type="description">
          <Button size="small" leadingVisual={PlusIcon} inactive>
            Add message pair
          </Button>
        </Tooltip>
      )}
    </div>
  )
}
