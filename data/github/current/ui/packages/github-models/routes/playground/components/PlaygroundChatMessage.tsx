import {ActionList, ActionMenu, IconButton} from '@primer/react'
import type {ModelState, PlaygroundMessage} from '../../../types'
import {PlaygroundError} from './PlaygroundError'
import {PlaygroundChatSuggestion, TokenLimitReachedResponseErrorDescription} from '../../../utils/playground-types'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {ThumbsdownIcon, ThumbsupIcon, SyncIcon, PencilIcon, NorthStarIcon} from '@primer/octicons-react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {FeedbackDialog} from '../../../components/FeedbackDialog'
import {Feedback} from './GettingStartedDialog/types'
import {sendFeedback} from '../../../utils/feedback'
import {textFromMessageContent} from '../../../utils/message-content-helper'
import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import styles from './PlaygroundChatMessage.module.css'
import {clsx} from 'clsx'
import {announceFromElement} from '@github-ui/aria-live'
import {testIdProps} from '@github-ui/test-id-props'
import type {Model} from '@github-ui/marketplace-common'
import {ModelSuggestionMenu} from './ModelSuggestionMenu'
import {sendEvent} from '@github-ui/hydro-analytics'

export const FeedbackValue = {
  POSITIVE: 'POSITIVE',
  NEGATIVE: 'NEGATIVE',
} as const

const promptImprovementSuggestions = [
  {action: 'cite_sources', task: 'Cite sources in response', prompt: 'Cite the sources in the response.'},
]

const modelSuggestions = [
  {action: 'make_response_cheaper', task: 'Make response cheaper'},
  {action: 'make_response_faster', task: 'Make response faster'},
]

export type FeedbackValue = (typeof FeedbackValue)[keyof typeof FeedbackValue]

export type PlaygroundChatMessageProps = {
  isLoading: boolean
  isError: boolean
  index: number
  message: PlaygroundMessage
  // temporary optional until Prompt uses regenerate
  handleRegenerate?: (index: number) => void
  handleEdit?: (index: number) => void
  lastIndex: boolean
  model: ModelState
  handleClearHistory: () => void
  handleImproveSuggestion?: (index: number, s: string) => void
  lowRateLimitTierModels?: Model[]
}

export function PlaygroundChatMessage({
  isLoading,
  isError,
  message,
  index,
  handleRegenerate,
  handleEdit,
  lastIndex,
  model,
  handleClearHistory,
  handleImproveSuggestion,
  lowRateLimitTierModels,
}: PlaygroundChatMessageProps) {
  const {catalogData} = model
  const [selectedSuggestions, setSelectedSuggestions] = useState<string[]>([])

  const messageTextContent = useMemo(() => {
    return textFromMessageContent(message.message)
  }, [message.message])

  const returnFocusRef = useRef(null)
  const messageRef = useRef(null)
  const [submittedFeedback, setSubmittedFeedback] = useState<
    typeof FeedbackValue.POSITIVE | typeof FeedbackValue.NEGATIVE | undefined
  >(undefined)

  const positiveFeedbackSubmitted = submittedFeedback === FeedbackValue.POSITIVE
  const [isFeedbackDialogOpen, setIsFeedbackDialogOpen] = useState(false)
  // In order to submit negative feedback, the user must click the thumbs down icon and then click the "Submit feedback" button in a dialog
  const [isNegativeFeedbackConfirmed, setIsNegativeFeedbackConfirmed] = useState(false)

  const isAssistantMessage = message.role === 'assistant' && message.message
  const isLastResponse = isAssistantMessage && lastIndex

  const images = (Array.isArray(message.message) && message.message.filter(m => m.type === 'image_url')) || []

  // Heuristic to determine if we're rendering JSON or markdown. We can't actually parse
  // because we're probably halfway through a streamed message
  const isProbablyJSON = (content: string) => content.trim().startsWith('{') || content.trim().startsWith('[')

  useEffect(() => {
    if (!isLoading && lastIndex && messageRef.current) {
      announceFromElement(messageRef.current)
    }
  }, [isLoading, lastIndex])

  const handleSubmit = async () => {
    const feedback = {
      satisfaction: Feedback.POSITIVE,
      reasons: [],
      feedbackText: '',
      contactConsent: false,
      model: catalogData.name,
    }
    try {
      const res = await sendFeedback({model: catalogData, feedback})
      if (res.ok) {
        setSubmittedFeedback(FeedbackValue.POSITIVE)
      }
    } catch (error) {
      return error
    }
  }

  const handleClick = useCallback(() => {
    setIsFeedbackDialogOpen(true)
    setSubmittedFeedback(FeedbackValue.NEGATIVE)
  }, [])

  if (message.role === 'tool') {
    return null
  }

  // Currently, the content will stream in with one format and is then re-indented at the end
  // This will fall through to the catch for every streamed chunk but the last.
  const wrapInJsonCodeBlock = (content: string) => {
    let formattedContent

    try {
      formattedContent = JSON.stringify(JSON.parse(content.trim()), null, 2)
    } catch {
      if (model.responseFormat === 'json_schema') {
        // Format partial JSON schema response while streaming for readability
        formattedContent = content.trim().replaceAll('{', '{\n').replaceAll('}', '\n}').replaceAll(',', ',\n')
      } else {
        formattedContent = content.trim() // Fallback to the original content
      }
    }

    return `\`\`\`json\n${formattedContent}\n\`\`\``
  }

  return (
    <div key={index} className={styles.playgroundChatMessagesContainer} {...testIdProps('playground-chat-message')}>
      {isError ? (
        <PlaygroundError
          message={messageTextContent}
          showResetButton={messageTextContent === TokenLimitReachedResponseErrorDescription}
          handleClearHistory={handleClearHistory}
        />
      ) : (
        <div className="position-relative">
          <div className="p-1" dir="auto" ref={messageRef}>
            {isProbablyJSON(messageTextContent) ? (
              <MarkdownRenderer markdown={wrapInJsonCodeBlock(messageTextContent)} />
            ) : (
              <MarkdownRenderer markdown={messageTextContent} />
            )}
            {images.length > 0 &&
              images.map(image => (
                <div className="py-2" key={image.image_url.url}>
                  <img
                    className="color-bg-subtle p-3 rounded-2"
                    src={image.image_url.url}
                    alt="Attachment"
                    height={200}
                  />
                </div>
              ))}
          </div>
          {isAssistantMessage && !isLoading && (
            <div className={clsx('message-actions', styles.messageActions, isLastResponse && styles.lastResponse)}>
              {!isNegativeFeedbackConfirmed && (
                <IconButton
                  className={clsx(positiveFeedbackSubmitted ? 'bGcolor-muted' : 'bGcolor-default')}
                  icon={ThumbsupIcon}
                  variant="invisible"
                  aria-label="Positive"
                  onClick={handleSubmit}
                  disabled={positiveFeedbackSubmitted}
                />
              )}
              {submittedFeedback !== FeedbackValue.POSITIVE && (
                <IconButton
                  className={clsx(isNegativeFeedbackConfirmed ? 'bGcolor-muted' : 'bGcolor-default')}
                  icon={ThumbsdownIcon}
                  variant="invisible"
                  aria-label="Negative"
                  onClick={handleClick}
                  disabled={isNegativeFeedbackConfirmed}
                />
              )}
              <CopyToClipboardButton textToCopy={messageTextContent} ariaLabel="Copy to clipboard" />
              {isLastResponse && handleRegenerate && (
                <IconButton
                  icon={SyncIcon}
                  variant="invisible"
                  aria-label="Regenerate"
                  onClick={() => handleRegenerate(index)}
                />
              )}
              {isLastResponse && handleEdit && (
                <ActionMenu>
                  <ActionMenu.Button variant="invisible" aria-label="Edit prompt menu" size="small">
                    <PencilIcon className="fgColor-muted" />
                  </ActionMenu.Button>
                  <ActionMenu.Overlay width="medium">
                    <ActionList>
                      <ActionList.Item onSelect={() => handleEdit(index)}>
                        Edit prompt
                        <ActionList.LeadingVisual>
                          <PencilIcon />
                        </ActionList.LeadingVisual>
                      </ActionList.Item>
                      {handleImproveSuggestion && (
                        <>
                          <ActionList.Divider />
                          <ActionList.GroupHeading {...testIdProps('playground-chat-message-improvement-suggestions')}>
                            Suggestions
                          </ActionList.GroupHeading>
                          {promptImprovementSuggestions.map(suggestion => (
                            <ActionList.Item
                              onSelect={() => {
                                sendEvent(`${PlaygroundChatSuggestion}.${suggestion.action}.clicked`)
                                setSelectedSuggestions([...selectedSuggestions, suggestion.task])
                                handleImproveSuggestion(index, suggestion.prompt)
                              }}
                              disabled={selectedSuggestions.includes(suggestion.task)}
                              key={suggestion.task}
                            >
                              {suggestion.task}
                              <ActionList.LeadingVisual>
                                <NorthStarIcon />
                              </ActionList.LeadingVisual>
                            </ActionList.Item>
                          ))}
                          {catalogData.rate_limit_tier !== 'low' &&
                            lowRateLimitTierModels &&
                            lowRateLimitTierModels.length > 0 &&
                            modelSuggestions.map(suggestion => {
                              // Exception for OpenAI models
                              const filteredModels =
                                suggestion.action === 'make_response_faster' &&
                                catalogData.publisher.toLowerCase() === 'openai'
                                  ? lowRateLimitTierModels.filter(m => m.publisher.toLowerCase() === 'openai')
                                  : lowRateLimitTierModels
                              if (filteredModels.length === 0) return null
                              return (
                                <ModelSuggestionMenu
                                  key={suggestion.task}
                                  task={suggestion.task}
                                  action={suggestion.action}
                                  suggestedModels={filteredModels}
                                />
                              )
                            })}
                        </>
                      )}
                    </ActionList>
                  </ActionMenu.Overlay>
                </ActionMenu>
              )}
            </div>
          )}
          {submittedFeedback === FeedbackValue.NEGATIVE && (
            <FeedbackDialog
              isNegativePreSelected
              setIsNegativeFeedbackConfirmed={setIsNegativeFeedbackConfirmed}
              returnFocusRef={returnFocusRef}
              isFeedbackDialogOpen={isFeedbackDialogOpen}
              setIsFeedbackDialogOpen={setIsFeedbackDialogOpen}
              modelName={catalogData.name}
            />
          )}
        </div>
      )}
    </div>
  )
}
