import {PlusIcon, TrashIcon} from '@primer/octicons-react'
import {Button, IconButton, Tooltip} from '@primer/react'
import {testIdProps} from '@github-ui/test-id-props'
import {useState} from 'react'
import type {MessagePair} from '../../../types'
import {PromptAutocompleteInput} from './PromptAutocompleteInput'
import styles from './PromptMessagePair.module.css'
import {clsx} from 'clsx'

export type PromptMessagePairProps = {
  messagePairs: MessagePair[]
  setMessagePairs: (messagePairs: MessagePair[]) => void
  variableKeys: string[]
  onVariablesClick?: () => void
  variablesIcon?: React.ComponentType
}

export const messagePairLimit = 4

export function PromptMessagePair({
  messagePairs,
  setMessagePairs,
  variableKeys,
  onVariablesClick,
  variablesIcon,
}: PromptMessagePairProps) {
  const [hoveredPairIndex, setHoveredPairIndex] = useState<number | null>(null)

  const handleAddingMessagePair = () => {
    setMessagePairs([...messagePairs, {assistant: '', user: ''}])
  }

  const handleUpdatingUserPrompt = (userPrompt: string, index: number) => {
    setMessagePairs(messagePairs.map((pair, i) => (i === index ? {...pair, user: userPrompt} : pair)))
  }

  const handleUpdatingAssistantPrompt = (assistantPrompt: string, index: number) => {
    setMessagePairs(messagePairs.map((pair, i) => (i === index ? {...pair, assistant: assistantPrompt} : pair)))
  }

  const handleRemoveMessagePair = (index: number) => {
    setMessagePairs(messagePairs.filter((_, i) => i !== index))
    setHoveredPairIndex(null) // clear hover index in case the element is removed before onMouseLeave can fire
  }

  const divKey = (index: number) => `message-pair-${index}`

  return (
    <div>
      {messagePairs.map((pair, index) => (
        <div
          className={clsx(styles.messagePair, {[styles.messagePairHover]: hoveredPairIndex === index})}
          key={divKey(index)}
        >
          <div className="mb-3">
            <PromptAutocompleteInput
              label="Assistant"
              prompt={pair.assistant}
              setPromptInput={input => handleUpdatingAssistantPrompt(input, index)}
              variableKeys={variableKeys}
              textareaPlaceholder="Define how the model should reply. This response, along with the previous user prompt, will shape the next interaction."
              trailingVisual={
                <IconButton
                  size="small"
                  icon={TrashIcon}
                  variant="invisible"
                  aria-label={`Remove both to retain user and assistant alternation`}
                  onClick={() => handleRemoveMessagePair(index)}
                  onMouseEnter={() => setHoveredPairIndex(index)}
                  onMouseLeave={() => setHoveredPairIndex(null)}
                  {...testIdProps(`remove-message-pair-${index}-assistant`)}
                />
              }
            />
          </div>
          <div className="mb-3">
            <PromptAutocompleteInput
              label="User"
              prompt={pair.user}
              setPromptInput={prompt => handleUpdatingUserPrompt(prompt, index)}
              variableKeys={variableKeys}
              textareaPlaceholder="Ask the model something. The previous responses will be considered. You can also use {{input}}."
              trailingVisual={
                <IconButton
                  size="small"
                  icon={TrashIcon}
                  variant="invisible"
                  aria-label={`Remove both to retain user and assistant alternation`}
                  onClick={() => handleRemoveMessagePair(index)}
                  onMouseEnter={() => setHoveredPairIndex(index)}
                  onMouseLeave={() => setHoveredPairIndex(null)}
                  {...testIdProps(`remove-message-pair-${index}-user`)}
                />
              }
            />
          </div>
        </div>
      ))}
      <div className="d-flex gap-2">
        {onVariablesClick && (
          <Button
            size="small"
            onClick={onVariablesClick}
            leadingVisual={variablesIcon}
            {...testIdProps('edit-variables')}
          >
            Variables
          </Button>
        )}
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
    </div>
  )
}
