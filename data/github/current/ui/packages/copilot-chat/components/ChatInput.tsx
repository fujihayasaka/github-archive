import {sendEvent} from '@github-ui/hydro-analytics'
import {useQueries} from '@github-ui/react-query'
import {testIdProps} from '@github-ui/test-id-props'
import {CommandIconButton, ScopedCommands} from '@github-ui/ui-commands'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {PaperAirplaneIcon, PaperclipIcon, SquareFillIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import type {ReactNode, RefObject} from 'react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {copilotChatTextAreaId} from '../utils/constants'
import type {CopilotChatReference, FigmaReference, IssueReference} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {CopilotImageAttacher} from '../utils/copilot-image-attacher'
import {useChatAutocomplete} from '../utils/CopilotChatAutocompleteContext'
import {useChatState, useChatStateValues} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {useChatInput, useTextareaPreview} from '../utils/use-chat-input'
import {AttachmentMenu} from './AttachmentMenu'
import type {AttachmentMenuPanelType} from './AttachmentMenuPanelType'
import {Autocomplete} from './Autocomplete'
import styles from './ChatInput.module.css'
import {ChatInputReferences} from './ChatInputReferences'

interface ChatInputProps {
  textAreaRef?: React.RefObject<HTMLTextAreaElement>
  onSubmit?: (text: string) => Promise<void>
  onAbort?: () => void
  isStreaming?: boolean
  size?: 'small' | 'large'
  placeholder?: string
  onClickReference?: (event: React.MouseEvent<HTMLAnchorElement>, reference: CopilotChatReference) => void
}

interface BaseUserInputLink {
  originalText: string
  processedText: string
  type: 'issue' | 'pull-request' | 'discussion' | 'figma'
  loadedRefData?: boolean
}

interface IssueUserInputLink extends BaseUserInputLink {
  type: 'issue'
  linkNumber: number
  repository: {
    name: string
    owner: string
  }
}

interface FigmaUserInputLink extends BaseUserInputLink {
  type: 'figma'
  id?: string
}

type UserInputLink = IssueUserInputLink | FigmaUserInputLink

export const ChatInput = (props: ChatInputProps) => {
  const state = useChatState()
  const autocomplete = useChatAutocomplete()
  const manager = useChatManager()
  const maxMessagesReached = manager.maxMessagesReached()
  const slashCommandLoading = state.slashCommandLoading.state === 'loading'

  const {
    typingHasStarted,
    textAreaRef,
    textareaPreviewRef,
    textAreaPreviewContainerRef,
    text,
    setText,
    handleSubmit,
    handleSubmitToNewThread,
    handleScroll,
    handleChange,
    handleStop,
    handleFocus,
  } = useChatInput({
    isLoading:
      state.isWaitingOnCopilot ||
      slashCommandLoading ||
      state.currentReferences.some(x => x.type === 'image' && !x.attachment.isLoaded),
    onSubmit: props.onSubmit,
    onAbort: props.onAbort,
    textAreaRef: props.textAreaRef,
  })

  const [userInputLinks, setUserInputLinks] = useState<UserInputLink[]>([])
  const {processedText, processedRefs, changeDetected} = processUserInput(
    text,
    userInputLinks,
    state.mode === 'immersive',
  )

  if (copilotFeatureFlags.copilotUIRefs && changeDetected) {
    setText(processedText)
    setUserInputLinks([...userInputLinks, ...processedRefs])
  }

  const stopResponse = () => {
    sendEvent('dotcom_chat.activate', {target: 'CHAT_MESSAGE_STOP', mode: state.mode})
    void handleStop()
  }

  const sendMessage = () => void handleSubmit()

  const sendMessageToNewThread = () => void handleSubmitToNewThread()

  const placeholderText = state.isWaitingOnCopilot
    ? `Copilot is responding…`
    : state.defaultRecipient
      ? undefined
      : maxMessagesReached
        ? 'Message limit reached. To continue chatting with Copilot, start a new conversation.'
        : props.placeholder
          ? props.placeholder
          : 'Ask Copilot'

  if (state.defaultRecipient && text === '' && !typingHasStarted) {
    setText(`@${state.defaultRecipient} `)
  }

  const filteredUserInputLinks = useMemo(() => userInputLinks.filter(link => !link.loadedRefData), [userInputLinks])

  const combinedQueries = useQueries({
    queries: filteredUserInputLinks.map(link => ({
      enabled: copilotFeatureFlags.copilotUIRefs,
      queryKey: ['copilot', 'chat-links', 'item-url', link.originalText],
      queryFn: async () => {
        const response = await verifiedFetchJSON(`/copilot/chat-links?item_url=${link.originalText}`)

        if (!response.ok) {
          // TODO: Proper error handling https://github.com/github/copilot-productivity/issues/3717
        }

        const isIssueReference = (queryResponse: unknown): queryResponse is IssueReference => {
          return (queryResponse as IssueReference).type === 'issue'
        }

        const isFigmaReference = (queryResponse: unknown): queryResponse is FigmaReference => {
          return (queryResponse as FigmaReference).type === 'figma'
        }

        const queryResponse = await response.json()
        if (isIssueReference(queryResponse)) return queryResponse
        if (isFigmaReference(queryResponse)) return queryResponse
      },
    })),
    combine: results => {
      return {
        data: results.map(result => result.data),
        pending: results.some(result => result.isPending),
      }
    },
  })

  // Process completed network requests
  useEffect(() => {
    const filteredData = combinedQueries.data.filter((item): item is IssueReference | FigmaReference => !!item)
    if (!combinedQueries.pending && filteredData.length > 0) {
      for (const data of filteredData) {
        if (data.type === 'issue') {
          const repoIssue = data

          // If the issue is not already in the references, add it
          if (!state.currentReferences.find(ref => ref.type === 'issue' && ref.number === repoIssue.number)) {
            setUserInputLinks(prevLinks => {
              return prevLinks.map(prevLink => {
                if (prevLink.type === 'issue' && prevLink.linkNumber === repoIssue.number) {
                  return {
                    ...prevLink,
                    loadedRefData: true,
                  }
                }
                return prevLink
              })
            })
            manager.addReference(repoIssue, 'chatInput')
          }
          return
        }

        if (state.mode === 'immersive' && copilotFeatureFlags.immersiveFigmaIntegration && data.type === 'figma') {
          if (!state.currentReferences.find(ref => ref.type === 'figma' && ref.url === data.url)) {
            setUserInputLinks(prevLinks => {
              return prevLinks.map(prevLink => {
                if (prevLink.originalText === data.url) {
                  return {
                    ...prevLink,
                    id: data.id,
                    loadedRefData: true,
                  }
                }
                return prevLink
              })
            })
            manager.addReference(data, 'chatInput')
          }
        }
      }
    }
  }, [combinedQueries.pending, combinedQueries.data, manager, state.currentReferences, state.mode, userInputLinks])

  useEffect(() => {
    if (
      copilotFeatureFlags.copilotUIRefs &&
      (state.action === 'REMOVE_REFERENCES' || state.action === 'CLEAR_CURRENT_REFERENCES')
    ) {
      // Get the index of the non-matching references now that it's been removed
      const nonMatchingReferenceIndices = userInputLinks
        .map((userInputLink, index) => {
          const match = state.currentReferences.find(
            currentRef =>
              (currentRef.type === 'issue' &&
                userInputLink.type === 'issue' &&
                userInputLink.linkNumber === currentRef.number) ||
              (currentRef.type === 'figma' &&
                userInputLink.type === 'figma' &&
                userInputLink.originalText === currentRef.url),
          )
          return match ? -1 : index
        })
        .filter(index => index !== -1)

      // For each nonMatchingReferenceIndex, get the processedText
      const updatedText = text

      // Remove the nonMatchingReferenceIndices from the userInputLinks
      const updatedUserInputLinks = userInputLinks.filter((_, index) => !nonMatchingReferenceIndices.includes(index))
      setUserInputLinks(updatedUserInputLinks)

      // Remove the highlighting from the processedText
      setText(updatedText)

      // Reset the state to the default
      state.action = undefined

      return
    }
  }, [manager, state.currentReferences, state, userInputLinks, text, setText])

  const attachmentButtonRef = useRef<HTMLButtonElement>(null)

  const [attachmentMenuPanel, setAttachmentMenuPanel] = useState<AttachmentMenuPanelType | null>(null)
  const addAttachment = () => {
    sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU', mode: state.mode})
    setAttachmentMenuPanel(attachmentMenuPanel === 'attachment-types' ? null : 'attachment-types')
  }

  // For now, we are focused on building out image support in immersive mode only, and only for supported models.
  const {model} = useChatStateValues('model')
  const shouldShowImages =
    (copilotFeatureFlags.attachImagesImmersive && state.mode === 'immersive' && !!model.capabilities.supports.vision) ||
    false

  const abortController = useRef<AbortController | null>(null)
  // If we unmount, abort any inflight uploads
  useEffect(
    () => () => {
      abortController.current?.abort()
    },
    [],
  )

  const handleFileAttachment = useCallback(
    (files: FileList | null, uploadType: 'drag' | 'paste') => {
      if (!shouldShowImages || !files) return

      const allowedFiles = Array.from(files).filter(file => CopilotImageAttacher.isTypeAllowed(file.type, model))

      if (allowedFiles.length > 0) {
        const attacher = new CopilotImageAttacher(state, manager, autocomplete)
        for (const file of allowedFiles) {
          const controller = (abortController.current ||= new AbortController())
          void attacher.addImageAttachment(file, controller.signal, uploadType)
        }
      }
    },
    [shouldShowImages, model, state, manager, autocomplete],
  )

  const handlePaste: React.ClipboardEventHandler<HTMLTextAreaElement> = event => {
    const clipboardData = event.clipboardData
    if (clipboardData?.items) {
      const fileArray: File[] = []

      for (let i = 0; i < clipboardData.items.length; i++) {
        const item = clipboardData.items[i]
        if (item && item.kind === 'file') {
          const file = item.getAsFile()
          if (file) fileArray.push(file)
        }
      }

      if (fileArray.length > 0) {
        event.preventDefault()
        const dataTransfer = new DataTransfer()
        for (const file of fileArray) {
          dataTransfer.items.add(file)
        }
        handleFileAttachment(dataTransfer.files, 'paste')
      }
    }
  }

  const handleFileDrop = useCallback(
    (event: DragEvent) => {
      event.preventDefault()
      handleFileAttachment(event.dataTransfer?.files || null, 'drag')
    },
    [handleFileAttachment],
  )

  useEffect(() => {
    const chatInput = textAreaRef?.current
    if (!chatInput) return

    const handleDragOver = (event: DragEvent) => event.preventDefault()

    chatInput.addEventListener('dragover', handleDragOver)
    chatInput.addEventListener('drop', handleFileDrop)

    return () => {
      chatInput.removeEventListener('dragover', handleDragOver)
      chatInput.removeEventListener('drop', handleFileDrop)
    }
  }, [textAreaRef, shouldShowImages, handleFileDrop])

  return (
    <>
      <ScopedCommands
        commands={{
          'copilot-chat:stop-response': stopResponse,
          'copilot-chat:send-message': sendMessage,
          'copilot-chat:send-message-new-conversation': sendMessageToNewThread,
          'copilot-chat:add-attachment': addAttachment,
        }}
      >
        <form
          className={clsx(styles.container, {
            [styles.containerSmall]: props.size === 'small',
          })}
        >
          <ChatInputReferences
            className={styles.attachments}
            returnFocusRef={attachmentButtonRef}
            tokenSize={props.size === 'small' ? 'small' : 'medium'}
            isLoading={combinedQueries.pending && userInputLinks.some(link => !link.loadedRefData)}
            onClickReference={props.onClickReference}
          />

          <ScopedCommands.LimitKeybindingScope
            // The default bindings for these are 'escape' and 'enter', so we need to strictly limit scope to avoid
            // breaking all the menu and button functionalities that rely on those keys
            commandIds={['copilot-chat:stop-response', 'copilot-chat:send-message']}
            className={styles.inputContainer}
            ref={textAreaPreviewContainerRef}
          >
            <Autocomplete textAreaRef={textAreaRef}>
              <textarea
                autoFocus
                id={copilotChatTextAreaId}
                className={styles.input}
                autoComplete="off"
                autoCorrect="off"
                spellCheck="false"
                aria-multiline="true"
                onPaste={handlePaste}
                ref={textAreaRef}
                onScroll={handleScroll}
                onChange={handleChange}
                onFocus={handleFocus}
                placeholder={placeholderText}
                value={processedText}
                data-react-autofocus
                disabled={maxMessagesReached}
                {...testIdProps('copilot-chat-input-textarea')}
              />
            </Autocomplete>
            <TextareaPreview
              text={text}
              textareaPreviewRef={textareaPreviewRef}
              textInputRefs={userInputLinks}
              size={props.size}
            />
          </ScopedCommands.LimitKeybindingScope>

          <div className={styles.trailingActions}>
            <CommandIconButton
              commandId="copilot-chat:add-attachment"
              icon={PaperclipIcon}
              variant="invisible"
              ref={attachmentButtonRef}
              tooltipDirection="n"
            />

            {props.isStreaming || state.isWaitingOnCopilot ? (
              <StopButton />
            ) : (
              <SubmitButton
                isLoading={
                  slashCommandLoading || state.currentReferences.some(x => x.type === 'image' && !x.attachment.isLoaded)
                }
              />
            )}
          </div>
        </form>
      </ScopedCommands>
      <AttachmentMenu
        inputRef={textAreaRef}
        inputOnChange={handleChange}
        anchorRef={attachmentButtonRef}
        panel={attachmentMenuPanel}
        onPanelChange={setAttachmentMenuPanel}
      />
    </>
  )
}

type TextAreaPreviewProps = {
  text: string
  textInputRefs: UserInputLink[]
  textareaPreviewRef: RefObject<HTMLDivElement>
  size?: 'small' | 'large'
}

function TextareaPreview(props: TextAreaPreviewProps) {
  const {text, textareaPreviewRef, textInputRefs} = props
  const {mention, textAfterMention} = useTextareaPreview(props)

  const processedPreviewText = processPreviewText(text, textInputRefs)

  return (
    <div
      id="copilot-chat-textarea-preview"
      {...testIdProps('copilot-chat-input-textarea-preview')}
      aria-hidden
      className={styles.inputPreview}
      ref={textareaPreviewRef}
      role="presentation"
    >
      {mention ? (
        <>
          <span className={styles.token}>{mention}</span>
          {textAfterMention}
        </>
      ) : (
        <>{processedPreviewText}</>
      )}
    </div>
  )
}

function SubmitButton({isLoading}: {isLoading?: boolean}) {
  return (
    <CommandIconButton
      commandId="copilot-chat:send-message"
      variant="invisible"
      size="medium"
      icon={PaperAirplaneIcon}
      aria-label="Send now"
      disabled={isLoading}
      tooltipDirection="n"
    />
  )
}

function StopButton() {
  return (
    <CommandIconButton
      {...testIdProps('copilot-chat-stop-button')}
      commandId="copilot-chat:stop-response"
      variant="invisible"
      size="medium"
      icon={SquareFillIcon}
      tooltipDirection="n"
      sx={{bg: 'danger.subtle', color: 'danger.fg', ':hover': {bg: 'danger.muted'}}}
    />
  )
}

/**
 * Search the textarea input for supported github related links
 */
function processUserInput(
  userInput: string,
  previouslyFoundLinks: UserInputLink[],
  isImmersive: boolean,
): {processedText: string; processedRefs: UserInputLink[]; changeDetected: boolean} {
  const processedRefs: UserInputLink[] = []
  let changeDetected = false

  const githubIssueUrlPattern = /^(?:http:\/\/github\.localhost|https:\/\/github\.com)\/[^/]+\/[^/]+\/issues\/\d+$/
  const figmaUrlPattern = /^https:\/\/www\.figma\.com\/.+$/

  const processedText = userInput
    .split(' ')
    .map(text => {
      // Check for duplicates that have already been found
      if (processedRefs.find(ref => ref.originalText === text)) return text
      if (isImmersive && copilotFeatureFlags.immersiveFigmaIntegration && figmaUrlPattern.test(text)) {
        const prevLink = previouslyFoundLinks.find(link => link.originalText === text)
        if (prevLink) {
          changeDetected = true
          return prevLink.processedText
        }

        const cleanFigmaUrl = text.replace('https://www.', '')

        processedRefs.push({
          originalText: text,
          processedText: `${cleanFigmaUrl.length > 30 ? `${cleanFigmaUrl.substring(0, 30)}...` : cleanFigmaUrl}`,
          type: 'figma',
        })

        changeDetected = true
        return text
      }

      if (githubIssueUrlPattern.test(text)) {
        const prevLink = previouslyFoundLinks.find(link => link.originalText === text)
        if (prevLink) {
          if (prevLink.loadedRefData) {
            // successful network call
            // Need to trigger a change to keep the textarea in sync with the preview text
            changeDetected = true
            return prevLink.processedText
          } else {
            // network call is still ongoing, still how url in textarea
            return prevLink.originalText
          }
        } else {
          // transform issue link into #{issueNumber} format
          const splitIssueUrl = text.split('/')
          const issueNumber = splitIssueUrl[splitIssueUrl.length - 1]!
          const repoName = splitIssueUrl[splitIssueUrl.length - 3]!
          const ownerName = splitIssueUrl[splitIssueUrl.length - 4]!

          processedRefs.push({
            originalText: text,
            processedText: `#${issueNumber}`,
            type: 'issue',
            linkNumber: Number(issueNumber),
            repository: {
              name: repoName,
              owner: ownerName,
            },
          })
          changeDetected = true
          return text
        }
      }

      return text
    })
    .join(' ')

  return {
    processedText,
    processedRefs,
    changeDetected,
  }
}

/**
 * Add additional UI features to detected GitHub Links/Refs.
 */
function processPreviewText(text: string, textInputRefs: UserInputLink[]): Array<string | ReactNode> {
  const processedPreviewText: Array<string | ReactNode> = []
  const words = text.split(' ')

  for (let i = 0; i < words.length; i++) {
    const word = words[i]
    let processedWord: string | React.ReactNode = word

    const inputRef = textInputRefs.find(ref => ref.originalText === word || ref.processedText === word)

    if ((inputRef && inputRef.loadedRefData) || inputRef?.type === 'figma') {
      processedWord = (
        <div
          key={i}
          className={styles.issueRefLink}
          {...testIdProps(inputRef.type === 'figma' ? 'figma-ref-link' : 'issue-ref-link')}
        >
          {inputRef.processedText}
        </div>
      )
    }

    processedPreviewText.push(processedWord)

    // We need to re-inject spaces between these words (except after the last word)
    if (i < words.length - 1) {
      processedPreviewText.push(' ')
    }
  }

  return processedPreviewText
}
