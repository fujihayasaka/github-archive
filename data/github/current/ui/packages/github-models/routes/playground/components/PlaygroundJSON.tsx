import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import React, {lazy, useCallback, useEffect, useState} from 'react'
import {usePlaygroundManager} from '../../../utils/playground-manager'
import {PlaygroundChatInput} from './PlaygroundChatInput'
import type {ModelState} from '../../../types'
import {ModelLegalTerms} from './GettingStartedDialog/ModelLegalTerms'
import {isValidPlaygroundMessageJSON, validateJSONAsPlaygroundMessages} from './playground-message-utils'
import {PlaygroundJSONEditModeToolbar} from './PlaygroundJSONEditModeToolbar'
import {PlaygroundJSONViewModeToolbar} from './PlaygroundJSONViewModeToolbar'
const CodeMirror = lazy(() => import('@github-ui/code-mirror'))

export type PlaygroundJSONProps = {
  model: ModelState
  position: number
  setToolbarContent: React.Dispatch<React.SetStateAction<React.ReactNode>>
  setFullWidthToolbarContent: React.Dispatch<React.SetStateAction<React.ReactNode>>
  stopStreamingMessages: () => void
  sendMessage: (message: string, attachments: string[]) => void
}

export function PlaygroundJSON({
  model,
  position,
  setToolbarContent,
  setFullWidthToolbarContent,
  stopStreamingMessages,
  sendMessage,
}: PlaygroundJSONProps) {
  const [initialContent, setInitialContent] = useState<string>(() => JSON.stringify(model.messages, null, 2))
  const [content, setContent] = useState<string>(initialContent)
  const [isValidJSON, setIsValidJSON] = useState<boolean>(true)
  const [editMode, setEditMode] = useState<boolean>(false)

  const manager = usePlaygroundManager()

  const onChange = (input: string) => {
    setContent(input)
    setIsValidJSON(isValidPlaygroundMessageJSON(input))
  }

  const applyInput = useCallback(
    (input: string) => {
      if (!isValidPlaygroundMessageJSON(input)) {
        return
      }

      const parsed = validateJSONAsPlaygroundMessages(input)
      if (parsed) {
        manager.setMessages(position, parsed)
        setInitialContent(input)
        setEditMode(false)
      }
    },
    [manager, position],
  )

  const resetInput = useCallback(() => {
    setContent(initialContent)
    setIsValidJSON(true)
    setEditMode(false)
  }, [initialContent])

  const renderToolbar = useCallback(() => {
    const doEdit = () => {
      stopStreamingMessages()
      setEditMode(true)
    }

    if (!editMode) {
      return <PlaygroundJSONViewModeToolbar doEdit={doEdit} />
    } else {
      return (
        <PlaygroundJSONEditModeToolbar
          applyInput={applyInput}
          content={content}
          initialContent={initialContent}
          isValidJSON={isValidJSON}
          resetInput={resetInput}
        />
      )
    }
  }, [applyInput, content, editMode, initialContent, isValidJSON, resetInput, stopStreamingMessages])

  useEffect(() => {
    setFullWidthToolbarContent(editMode ? renderToolbar() : null)
    setToolbarContent(!editMode ? renderToolbar() : null)

    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [content, initialContent, isValidJSON, editMode])

  // Important if last session is restored by the user
  useEffect(() => {
    const _content = JSON.stringify(model.messages, null, 2)
    setInitialContent(_content)
    setContent(_content)
  }, [model.messages])

  return (
    <div className="pl-3 pb-2 d-flex position-relative flex-column overflow-auto flex-1">
      <CopyToClipboardButton
        className="position-absolute"
        sx={{right: '8px', top: '8px', zIndex: 10}}
        textToCopy={initialContent}
        ariaLabel={'Copy to clipboard'}
      />

      <div className="height-full overflow-auto">
        <React.Suspense fallback={<></>}>
          <CodeMirror
            fileName={`document.json`}
            value={content}
            ariaLabelledBy={''}
            height="100%"
            spacing={{
              indentUnit: 2,
              indentWithTabs: false,
              lineWrapping: true,
            }}
            hideHelpUntilFocus
            onChange={onChange}
            isReadOnly={!editMode || model.isLoading}
          />
        </React.Suspense>
      </div>

      {!editMode && (
        <>
          <PlaygroundChatInput
            model={model}
            position={position}
            stopStreamingMessages={stopStreamingMessages}
            sendMessage={sendMessage}
          />
          <div className="pt-3 pb-2 d-flex flex-justify-center pr-3">
            <ModelLegalTerms modelName={model.catalogData.name} />
          </div>
        </>
      )}
    </div>
  )
}
