import {testIdProps} from '@github-ui/test-id-props'
import CopilotBadge from '@github-ui/copilot-chat/components/CopilotBadge'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {Box, IconButton, RelativeTime, Text} from '@primer/react'
import {useUser} from '@github-ui/use-user'

import type {ModelState, PlaygroundMessage} from '../../../types'
import {PlaygroundError} from './PlaygroundError'
import {TokenLimitReachedResponseErrorDescription} from '../../../utils/playground-types'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {ThumbsdownIcon, ThumbsupIcon, SyncIcon} from '@primer/octicons-react'
import {useCallback, useMemo, useRef, useState} from 'react'
import {FeedbackDialog} from './GettingStartedDialog/FeedbackDialog'
import {Feedback} from './GettingStartedDialog/types'
import {sendFeedback} from '../../../utils/feedback'
import {textFromMessageContent} from '../../../utils/message-content-helper'
import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import ModelsAvatar from '../../../components/ModelsAvatar'

export enum FeedbackValue {
  POSITIVE,
  NEGATIVE,
}

export type PlaygroundChatMessageProps = {
  isLoading: boolean
  isError: boolean
  index: number
  message: PlaygroundMessage
  handleRegenerate: (index: number) => void
  lastIndex: boolean
  model: ModelState
  handleClearHistory: () => void
}

export function PlaygroundChatMessage({
  isLoading,
  isError,
  message,
  index,
  handleRegenerate,
  lastIndex,
  model,
  handleClearHistory,
}: PlaygroundChatMessageProps) {
  const {catalogData} = model

  const messageTextContent = useMemo(() => {
    return textFromMessageContent(message.message)
  }, [message.message])

  const user = useUser()
  const returnFocusRef = useRef(null)
  const [submittedFeedback, setSubmittedFeedback] = useState<
    FeedbackValue.POSITIVE | FeedbackValue.NEGATIVE | undefined
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

  const determineMessageMeta = (_message: PlaygroundMessage) => {
    switch (_message.role) {
      case 'error':
      case 'assistant':
        return {
          name: catalogData.name,
          avatarUrl: catalogData.logo_url,
        }
      case 'user':
        return {
          name: user.currentUser?.name ?? 'User',
          avatarUrl: user.currentUser?.avatarUrl ?? '/github.png',
        }
      default:
        return {
          name: 'default',
          avatarUrl: '/github.png',
        }
    }
  }

  const messageMeta = determineMessageMeta(message)

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

  const customIcon =
    message.role === 'assistant' || message.role === 'error' ? (
      <ModelsAvatar model={catalogData} size={12} />
    ) : (
      <GitHubAvatar src={messageMeta.avatarUrl} size={12} square={message.role !== 'user'} />
    )

  return (
    <Box
      key={index}
      sx={{
        pb: 2,
        '&:hover, &:focus-within': {
          '.message-actions': {
            opacity: 1,
            pointerEvents: 'auto',
          },
        },
        // We don’t want delay for keyboard users
        '&:hover': {
          '.message-actions': {
            transition: 'opacity 0.1s ease-in-out',
            transitionDelay: '0.2s',
          },
        },
      }}
    >
      <Box
        className="message-container"
        {...testIdProps('playground-chat-message')}
        tabIndex={0}
        // ref={myRef}
        sx={{
          p: 1,
          // borderBottom: '1px solid var(--borderColor-muted, var(--color-border-muted))',
          fontSize: 1,
        }}
      >
        <Box
          sx={{
            width: '100%',
            display: 'flex',
            alignItems: 'center',
            gap: 2,
            fontSize: 1,
          }}
        >
          <CopilotBadge isLoading={isLoading} isError={isError} customIcon={customIcon} />

          <Box
            sx={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              flexGrow: 1,
            }}
          >
            <Box sx={{display: 'flex', gap: 2, alignItems: 'baseline'}}>
              <Text
                {...testIdProps('chat-message-author-name')}
                sx={{
                  fontWeight: 'bold',
                }}
              >
                {messageMeta.name}
              </Text>
              <Text
                sx={{
                  fontSize: 0,
                  fontWeight: 400,
                  color: 'fg.subtle',
                }}
              >
                {messageMeta.name !== 'user' && isLoading ? (
                  `Responding...`
                ) : (
                  <RelativeTime {...testIdProps('message-timestamp')} date={message.timestamp} format="relative" />
                )}
              </Text>
            </Box>
          </Box>
        </Box>
      </Box>
      {isError ? (
        <PlaygroundError
          message={messageTextContent}
          showResetButton={messageTextContent === TokenLimitReachedResponseErrorDescription}
          handleClearHistory={handleClearHistory}
        />
      ) : (
        <div className="position-relative">
          <div className="p-1">
            {isProbablyJSON(messageTextContent) ? (
              <p style={{whiteSpace: 'pre-wrap'}}>{messageTextContent.trim()}</p>
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
            <Box
              className="message-actions"
              sx={{
                display: 'inline-flex',
                alignItems: 'center',
                zIndex: 1,
                // Floating actions for previous messages
                position: isLastResponse ? undefined : 'absolute',
                bottom: isLastResponse ? undefined : '-2.25rem',
                backgroundColor: 'var(--bgColor-default, var(--color-canvas-default))',
                borderRadius: isLastResponse ? undefined : 2,
                boxShadow: isLastResponse ? undefined : 'var(--shadow-floating-small)',
                // Opacity and pointer events rules instead of changing `display` let us animate the actions in and out
                opacity: isLastResponse ? undefined : 0,
                pointerEvents: isLastResponse ? undefined : 'none',
                // This is not ideal but required to ensure the shadow is not completely clipped
                left: isLastResponse ? undefined : '2px',

                // Adds a lil invisible target to make hovering less precise so they don’t disappear if you miss a bit
                '&::before': {
                  // Not on the inline actions though
                  content: isLastResponse ? undefined : '""',
                  // Make it wider than it is tall to cover the triangular hover path
                  inset: '-0.5rem -0.75rem',
                  zIndex: -1,
                  position: 'absolute',
                },
              }}
            >
              {!isNegativeFeedbackConfirmed && (
                <IconButton
                  sx={{
                    backgroundColor: positiveFeedbackSubmitted ? 'canvas.subtle' : 'canvas.default',
                  }}
                  icon={ThumbsupIcon}
                  variant="invisible"
                  aria-label="Positive"
                  onClick={handleSubmit}
                  disabled={positiveFeedbackSubmitted}
                />
              )}
              {submittedFeedback !== FeedbackValue.POSITIVE && (
                <IconButton
                  sx={{
                    backgroundColor: isNegativeFeedbackConfirmed ? 'canvas.subtle' : 'canvas.default',
                  }}
                  icon={ThumbsdownIcon}
                  variant="invisible"
                  aria-label="Negative"
                  onClick={handleClick}
                  disabled={isNegativeFeedbackConfirmed}
                />
              )}
              <CopyToClipboardButton textToCopy={messageTextContent} ariaLabel="Copy to clipboard" />
              {isLastResponse && (
                <IconButton
                  icon={SyncIcon}
                  variant="invisible"
                  aria-label="Regenerate"
                  onClick={() => handleRegenerate(index)}
                />
              )}
            </Box>
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
    </Box>
  )
}
