import {sendEvent} from '@github-ui/hydro-analytics'
import {testIdProps} from '@github-ui/test-id-props'
import type {CommandId} from '@github-ui/ui-commands'
import {CommandIconButton, ScopedCommands} from '@github-ui/ui-commands'
import {useSyntheticChange} from '@github-ui/use-synthetic-change'
import {PaperAirplaneIcon, PaperclipIcon, RocketIcon, SquareFillIcon} from '@primer/octicons-react'
import {Button, useSafeTimeout} from '@primer/react'
import {clsx} from 'clsx'
import type {RefObject} from 'react'
import {memo, useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {useAddMentionReferences} from '../hooks/use-add-mention-references'
import {useAddUrlReferences} from '../hooks/use-add-url-references'
import {useChatInput} from '../hooks/use-chat-input'
import {copilotChatTextAreaId} from '../utils/constants'
import type {
  CopilotChatReference,
  CustomCopilotId,
  ImageReference,
  ThreadScopedFileReference,
} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {CopilotImageAttacher} from '../utils/copilot-image-attacher'
import {sendVisionErrorEvent} from '../utils/copilot-image-helpers'
import {CLIPBOARD_MIME_TYPE, CopilotTextAttacher} from '../utils/copilot-text-attacher'
import {useChatState, useChatStateValues} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {isCopilotSpacePath} from '../utils/custom-copilots-helpers'
import {AttachmentMenu} from './AttachmentMenu'
import type {AttachmentMenuPanelType} from './AttachmentMenuPanelType'
import {Autocomplete} from './Autocomplete'
import styles from './ChatInput.module.css'
import {ChatInputPreview} from './ChatInputPreview'
import {ChatInputReferences} from './ChatInputReferences'
import {ModelPicker} from './ModelPicker'
import {useEntitlement} from './quota/EntitlementContext'

/** When the user pastes text that is longer than this many characters, we will automatically convert it to a file. */
const PASTE_TEXT_AS_FILE_THRESHOLD = 1000

const LIMITED_KEYBINDING_COMMAND_IDS: CommandId[] = [
  'github:cancel',
  'copilot-chat:send-message',
  'copilot-chat:edit-last-message',
]

interface ChatInputProps {
  textAreaRef?: React.RefObject<HTMLTextAreaElement>
  onSubmit?: (text: string) => Promise<void>
  isStreaming?: boolean
  size?: 'small' | 'large'
  placeholder?: string
  onSelectReference?: (reference: CopilotChatReference, event?: React.MouseEvent<HTMLAnchorElement>) => void
  onNewThreadSelected?: () => Promise<void>
  showModelPicker?: boolean
  hideAttachmentButton?: boolean
  getReferenceVersion?: (reference: CopilotChatReference) => number | undefined
  /** Set of previously generated/referenced file names in this thread, to use as a reference for generating new file names. */
  existingFileNames?: Set<string>
  disabled?: boolean
  figmaAuthUrl?: string
  customCopilotId?: CustomCopilotId
}

export const ChatInput = (props: ChatInputProps) => {
  const state = useChatState()
  const manager = useChatManager()
  const maxMessagesReached = manager.maxMessagesReached()
  const [pastedFile, setPastedFile] = useState<File | null>(null)
  const slashCommandLoading = state.slashCommandLoading.state === 'loading'
  const {safeSetTimeout} = useSafeTimeout()
  const {isLicensedLimited} = useEntitlement()
  const {onSelectReference} = props
  const pastedFileNamePromise = useRef<Promise<string> | null>(null)
  const pastedFileName = useRef<string>('')

  const clearPastedFile = useCallback(() => {
    setPastedFile(null)
    pastedFileNamePromise.current = null
    pastedFileName.current = ''
  }, [])

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
    isLoading: state.isWaitingOnCopilot || state.isWaitingOnAttachment || slashCommandLoading,
    onSubmit: props.onSubmit,
    textAreaRef: props.textAreaRef,
    clearPastedFile,
  })

  const emitChange = useSyntheticChange({inputRef: textAreaRef, fallbackEventHandler: handleChange})
  const {isLoading: urlReferencesPending, replaceUrlWithReferenceMention} = useAddUrlReferences({
    figmaAuthUrl: props.figmaAuthUrl,
    textAreaRef,
    emitChange,
  })
  const {
    isLoading: mentionReferencesPending,
    addReferenceForMention,
    addReferencesForMentions,
  } = useAddMentionReferences()
  // Prevent thread selection when we attach images if we're in the space's page
  const preventThreadSelectionOnCreation = props?.customCopilotId && isCopilotSpacePath()

  const submitDisabled =
    slashCommandLoading || urlReferencesPending || mentionReferencesPending || state.isWaitingOnAttachment

  const textAreaEmpty = text.length === 0

  const stopResponse = useCallback(() => {
    sendEvent('dotcom_chat.activate', {target: 'CHAT_MESSAGE_STOP', mode: state.mode})
    void handleStop()
  }, [handleStop, state.mode])

  const sendMessage = useCallback(async () => {
    if (submitDisabled) return
    sendEvent('dotcom_chat.activate', {target: 'CHAT_MESSAGE_SUBMIT', mode: state.mode})

    // If we have a pendingThread from an image attachment, set it as the thread to use
    if (preventThreadSelectionOnCreation) {
      await manager.selectPendingThread(props?.customCopilotId)
    }

    if (pastedFile) {
      clearPastedFile()
    }
    void handleSubmit()
  }, [
    submitDisabled,
    state.mode,
    preventThreadSelectionOnCreation,
    pastedFile,
    handleSubmit,
    manager,
    props?.customCopilotId,
    clearPastedFile,
  ])

  const sendMessageToNewThread = useCallback(async () => {
    if (submitDisabled) return

    // If we have a pendingThread from an image attachment, set it as the thread to use
    if (preventThreadSelectionOnCreation) {
      await manager.selectPendingThread(props?.customCopilotId)
    }
    void handleSubmitToNewThread()
  }, [handleSubmitToNewThread, submitDisabled, manager, preventThreadSelectionOnCreation, props?.customCopilotId])

  const editLastMessage = useCallback(() => {
    const id = state.messages.findLast(m => m.role === 'user')?.id
    if (id) manager.startEditingMessage(id)
  }, [manager, state.messages])

  const placeholderText = state.isWaitingOnCopilot
    ? `Copilot is responding…`
    : state.defaultRecipient
      ? undefined
      : maxMessagesReached
        ? 'Message limit reached. To continue chatting with Copilot, start a new conversation.'
        : props.placeholder
          ? props.placeholder
          : 'How can I help you?'

  if (state.defaultRecipient && text === '' && !typingHasStarted) {
    setText(`@${state.defaultRecipient} `)
  }

  const attachmentButtonRef = useRef<HTMLButtonElement>(null)

  const [attachmentMenuPanel, setAttachmentMenuPanel] = useState<AttachmentMenuPanelType | null>(null)
  const addAttachment = useCallback(() => {
    sendEvent('dotcom_chat.activate', {target: 'ATTACHMENT_MENU', mode: state.mode})
    setAttachmentMenuPanel(panel => (panel === 'attachment-types' ? null : 'attachment-types'))
  }, [state.mode])

  const setDeepCodeSearch = useCallback(() => {
    sendEvent('dotcom_chat.activate', {target: 'DEEP_CODESEARCH', mode: state.mode})
    manager.dispatch({type: 'SET_DEEP_CODESEARCH', deepCodeSearch: !state.skillOptions?.deepCodeSearch})
  }, [manager, state.mode, state.skillOptions?.deepCodeSearch])

  // For now, we are focused on building out image support in immersive mode only, and only for supported models.
  const {model} = useChatStateValues('model')
  const shouldShowImages =
    (copilotFeatureFlags.attachImagesImmersive && state.mode === 'immersive' && !!model.capabilities.supports.vision) ||
    false

  const handleFileAttachment = useCallback(
    async (files: Iterable<File>, uploadType: 'drag' | 'paste', namePromise?: Promise<string>, name?: string) => {
      const imageAttacher = new CopilotImageAttacher(state, manager)
      const textAttacher = new CopilotTextAttacher(manager, props.existingFileNames)
      const attachedFiles: Array<ThreadScopedFileReference | ImageReference> = []

      const hasImageFiles = [...files].some(file => file.type.startsWith('image/'))
      if (hasImageFiles && !model.capabilities.supports.vision) {
        manager.addAmbientError(
          `The ${model.displayName} model doesn't support answering questions about images. Select a different model and try again.`,
        )
        sendVisionErrorEvent('vision_not_supported_for_model', {
          modelId: model.id,
          uploadType,
        })
      }

      // Split the image files out of the other files so we can handle them separately.
      const [imageFiles, otherFiles] = CopilotImageAttacher.getAllowedFiles([...files], model)

      if (shouldShowImages) {
        const imageAttachments = await imageAttacher.addImageAttachments(
          imageFiles,
          uploadType,
          props.customCopilotId,
          preventThreadSelectionOnCreation,
        )
        if (imageAttachments) attachedFiles.push(...imageAttachments)
      }

      const disallowedFileTypes = []
      for (const file of otherFiles) {
        if (copilotFeatureFlags.pasteTextFiles && (await CopilotTextAttacher.isAttachable(file))) {
          const attachedFile = await textAttacher.addAttachment(file, namePromise, name)
          if (attachedFile) attachedFiles.push(attachedFile)
        } else disallowedFileTypes.push(file.type)
      }

      if (shouldShowImages && disallowedFileTypes.length > 0) {
        sendVisionErrorEvent('included_unsupported_file', {
          fileTypes: disallowedFileTypes.join(','),
          uploadType,
        })
      }
      return attachedFiles
    },
    [
      shouldShowImages,
      model,
      state,
      manager,
      props.existingFileNames,
      props.customCopilotId,
      preventThreadSelectionOnCreation,
    ],
  )

  const handleConvertToFile = useCallback(async () => {
    if (!pastedFile) return
    const fileArray = [pastedFile]
    const attachments = await handleFileAttachment(
      fileArray,
      'paste',
      pastedFileNamePromise.current || undefined,
      pastedFileName.current,
    )
    if (attachments.length > 0 && attachments[0]?.type === 'thread-scoped-file') {
      const pastedText = await pastedFile.text()
      const newText = text.replaceAll(pastedText, `@${attachments[0].name}`)
      setText(newText)
      clearPastedFile()
      onSelectReference?.(attachments[0])
    }
    sendEvent('dotcom_chat.activate', {target: 'CONVERT_TO_FILE', mode: state.mode})
  }, [pastedFile, handleFileAttachment, state.mode, text, setText, clearPastedFile, onSelectReference])

  const handleConvertToFileDismiss = useCallback(() => {
    clearPastedFile()
  }, [clearPastedFile])

  const handlePaste: React.ClipboardEventHandler<HTMLTextAreaElement> = event => {
    const clipboardData = event.clipboardData
    if (clipboardData?.items) {
      const fileArray: File[] = []

      for (let i = 0; i < clipboardData.items.length; i++) {
        const item = clipboardData.items[i]
        if (!item) continue

        if (item.kind === 'file') {
          const file = item.getAsFile()
          if (file) fileArray.push(file)
        } else if (
          item.kind === 'string' &&
          ['text', 'text/plain'].includes(item.type) // "text" for tests, "text/plain" for real clipboard
        ) {
          const pastedText = clipboardData.getData(item.type)

          if (
            copilotFeatureFlags.pasteTextFiles &&
            pastedText.length > PASTE_TEXT_AS_FILE_THRESHOLD &&
            pastedText.length <= CopilotTextAttacher.getAttachmentSizeLimit()
          ) {
            // Run after the input value updates.
            safeSetTimeout(() => {
              const file = new File([pastedText], '', {type: CLIPBOARD_MIME_TYPE})
              const textAttacher = new CopilotTextAttacher(manager, props.existingFileNames)
              setPastedFile(file)
              const namePromise = textAttacher
                .generateFileName(pastedText, file.type)
                // eslint-disable-next-line github/no-then
                .then(name => (pastedFileName.current = name))
              pastedFileNamePromise.current = namePromise
            }, 1)
          } else {
            addReferencesForMentions(pastedText)

            const insertionIndex = textAreaRef.current?.selectionStart ?? 0
            // After the paste completes, process the pasted text for URLs. Doing it this way (as opposed to preventing
            // the paste and setting the value synchronously) preserves the undo stack, allowing users to undo the
            // URL replacing if they want
            setTimeout(() => replaceUrlWithReferenceMention([insertionIndex, insertionIndex + pastedText.length]))
            return
          }
        }
      }

      if (fileArray.length > 0) {
        event.preventDefault()
        void handleFileAttachment(fileArray, 'paste')
      }
    }
  }

  const handleFileDrop = useCallback(
    (event: DragEvent) => {
      event.preventDefault()
      const files = event.dataTransfer?.files
      if (files) void handleFileAttachment(files, 'drag')
    },
    [handleFileAttachment],
  )

  const wholeAreaDragDrop = shouldShowImages && copilotFeatureFlags.wholeAreaDragDrop
  useEffect(() => {
    if (wholeAreaDragDrop && !props.customCopilotId) return

    const chatInput = textAreaRef?.current
    if (!chatInput) return

    const handleDragOver = (event: DragEvent) => event.preventDefault()

    chatInput.addEventListener('dragover', handleDragOver)
    chatInput.addEventListener('drop', handleFileDrop)

    return () => {
      chatInput.removeEventListener('dragover', handleDragOver)
      chatInput.removeEventListener('drop', handleFileDrop)
    }
  }, [textAreaRef, wholeAreaDragDrop, handleFileDrop, props.customCopilotId])

  const stoppable = props.isStreaming || state.isWaitingOnCopilot

  return (
    <>
      <ScopedCommands
        commands={useMemo(
          () => ({
            // avoid hijacking the escape key unless there is some streaming to cancel
            'github:cancel': stoppable ? stopResponse : undefined,
            'copilot-chat:send-message': sendMessage,
            'copilot-chat:send-message-new-conversation': sendMessageToNewThread,
            'copilot-chat:add-attachment': addAttachment,
            'copilot-chat:edit-last-message': textAreaEmpty ? editLastMessage : undefined,
            'copilot-chat:deep-codesearch': setDeepCodeSearch,
          }),
          [
            addAttachment,
            editLastMessage,
            sendMessage,
            sendMessageToNewThread,
            setDeepCodeSearch,
            stopResponse,
            stoppable,
            textAreaEmpty,
          ],
        )}
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
            isLoading={urlReferencesPending || mentionReferencesPending}
            onSelectReference={onSelectReference}
            getReferenceVersion={props.getReferenceVersion}
            showConvertToFileText={!!pastedFile && !state.isWaitingOnAttachment}
            onConvertToFile={handleConvertToFile}
            onConvertToFileDismiss={handleConvertToFileDismiss}
          />

          <ScopedCommands.LimitKeybindingScope
            // The default bindings for these are 'escape' and 'enter', so we need to strictly limit scope to avoid
            // breaking all the menu and button functionalities that rely on those keys
            commandIds={LIMITED_KEYBINDING_COMMAND_IDS}
            className={styles.inputContainer}
            ref={textAreaPreviewContainerRef}
          >
            <Autocomplete onSelectReference={addReferenceForMention} onShowAgentsDialog={setAttachmentMenuPanel}>
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
                value={text}
                data-react-autofocus
                disabled={maxMessagesReached || props.disabled}
                {...testIdProps('copilot-chat-input-textarea')}
              />
            </Autocomplete>
            <ChatInputPreview text={text} ref={textareaPreviewRef} />
          </ScopedCommands.LimitKeybindingScope>
          <ChatInputToolbar
            addAttachment={addAttachment}
            attachmentButtonRef={attachmentButtonRef}
            deepCodeSearch={state.skillOptions?.deepCodeSearch}
            hideAttachmentButton={!!props.hideAttachmentButton}
            stoppable={stoppable}
            submitDisabled={submitDisabled}
            onNewThreadSelected={props.onNewThreadSelected}
            showModelPicker={props.showModelPicker}
            isLicensedLimited={isLicensedLimited}
          />
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

const ChatInputToolbar = memo(
  ({
    addAttachment,
    attachmentButtonRef,
    deepCodeSearch,
    hideAttachmentButton,
    stoppable,
    submitDisabled,
    onNewThreadSelected,
    showModelPicker,
    isLicensedLimited,
  }: {
    addAttachment: () => void
    attachmentButtonRef: RefObject<HTMLButtonElement>
    deepCodeSearch: boolean | undefined
    hideAttachmentButton: boolean
    stoppable: boolean
    submitDisabled: boolean
    onNewThreadSelected?: () => Promise<void>
    showModelPicker?: boolean
    isLicensedLimited?: boolean
  }) => {
    return (
      <div className={styles.toolbar}>
        <div className={styles.toolbarLeft}>
          {copilotFeatureFlags.showDeepCodeSearchButton && (
            <CommandIconButton
              commandId="copilot-chat:deep-codesearch"
              icon={RocketIcon}
              variant="invisible"
              tooltipDirection="n"
              className={clsx({
                [styles.clicked]: deepCodeSearch,
              })}
            />
          )}
          {!hideAttachmentButton && (
            <Button
              ref={attachmentButtonRef}
              leadingVisual={PaperclipIcon}
              variant="invisible"
              onClick={addAttachment}
              data-testid="attachment-menu-button"
            >
              Attach
            </Button>
          )}
        </div>
        <div className={styles.toolbarRight}>
          {onNewThreadSelected && showModelPicker && (
            <ModelPicker onNewThreadSelected={onNewThreadSelected} limited={isLicensedLimited} />
          )}
          {stoppable ? <StopButton /> : <SubmitButton disabled={submitDisabled} />}
        </div>
      </div>
    )
  },
)
ChatInputToolbar.displayName = 'ChatInputToolbar'

function SubmitButton({disabled}: {disabled?: boolean}) {
  return (
    <CommandIconButton
      commandId="copilot-chat:send-message"
      variant="invisible"
      size="medium"
      icon={PaperAirplaneIcon}
      aria-label="Send now"
      disabled={disabled}
      tooltipDirection="n"
    />
  )
}

function StopButton() {
  return (
    <CommandIconButton
      {...testIdProps('copilot-chat-stop-button')}
      commandId="github:cancel"
      variant="invisible"
      size="medium"
      icon={SquareFillIcon}
      tooltipDirection="n"
      sx={{bg: 'danger.subtle', color: 'danger.fg', ':hover': {bg: 'danger.muted'}}}
    />
  )
}
