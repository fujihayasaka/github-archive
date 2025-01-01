import type {CopilotChatManager} from '@github-ui/copilot-chat/utils/copilot-chat-manager'
import type {CopilotChatState} from '@github-ui/copilot-chat/utils/copilot-chat-reducer'
import type {CopilotChatModel} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {CopilotImageAttacher} from '@github-ui/copilot-chat/utils/copilot-image-attacher'
import {sendVisionErrorEvent} from '@github-ui/copilot-chat/utils/copilot-image-helpers'
import {CopilotTextAttacher} from '@github-ui/copilot-chat/utils/copilot-text-attacher'
import type {ReactNode} from 'react'
import {createContext, useCallback, useContext, useEffect, useMemo, useState} from 'react'

type DragDropContextType = {
  isDragging: boolean
}

const DragDropContext = createContext<DragDropContextType | undefined>(undefined)

export function useDragDropContext() {
  const ctx = useContext(DragDropContext)
  if (!ctx) throw new Error('useDragDropContext must be used within DragDropProvider')
  return ctx
}

interface DragDropProviderProps {
  children: ReactNode
  model: CopilotChatModel
  state: CopilotChatState
  manager: CopilotChatManager
}

export function DragDropProvider({children, model, state, manager}: DragDropProviderProps) {
  const [isDragging, setIsDragging] = useState(false)

  const handleFileAttachment = useCallback(
    async (files: FileList | null, uploadType: 'drag' | 'paste') => {
      if (!files) return

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

      const [imageFiles, otherFiles] = CopilotImageAttacher.getAllowedFiles([...files], model)
      if (imageFiles.length > 0) {
        const attacher = new CopilotImageAttacher(state, manager)
        void attacher.addImageAttachments(imageFiles, uploadType)
      }
      if (copilotFeatureFlags.pasteTextFiles && otherFiles.length > 0) {
        const disallowedFileTypes: string[] = []
        const textAttacher = new CopilotTextAttacher(manager)

        await Promise.allSettled(
          otherFiles.map(async file => {
            if (await CopilotTextAttacher.isAttachable(file)) {
              await textAttacher.addAttachment(file)
            } else {
              disallowedFileTypes.push(file.type)
            }
          }),
        )
        if (disallowedFileTypes.length > 0) {
          sendVisionErrorEvent('included_unsupported_file', {
            fileTypes: disallowedFileTypes.join(','),
            uploadType,
          })
        }
      }
    },
    [model, state, manager],
  )

  useEffect(() => {
    const handleDrop = (event: DragEvent) => {
      event.preventDefault()
      setIsDragging(false)
      void handleFileAttachment(event.dataTransfer?.files || null, 'drag')
    }

    const handleDragOver = (event: DragEvent) => {
      event.preventDefault()
    }

    const handleDragEnter = () => {
      setIsDragging(true)
    }

    const handleDragLeave = () => {
      setIsDragging(false)
    }

    window.addEventListener('dragover', handleDragOver)
    window.addEventListener('drop', handleDrop)
    window.addEventListener('dragenter', handleDragEnter)
    window.addEventListener('dragleave', handleDragLeave)

    return () => {
      window.removeEventListener('dragover', handleDragOver)
      window.removeEventListener('drop', handleDrop)
      window.removeEventListener('dragenter', handleDragEnter)
      window.removeEventListener('dragleave', handleDragLeave)
    }
  }, [handleFileAttachment])

  const contextValue = useMemo(() => ({isDragging}), [isDragging])
  return <DragDropContext.Provider value={contextValue}>{children}</DragDropContext.Provider>
}
