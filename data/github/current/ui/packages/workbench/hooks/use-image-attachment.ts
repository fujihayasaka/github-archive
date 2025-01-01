import {useCallback, useState} from 'react'

import type {WorkbenchMediaContentItem} from '../types/workbench-types'

export const IMAGE_ATTACHMENT_SIZE_LIMIT = 3.75 * 1000 * 1024 // Claude only supports up to 3.75MB

export const processImageAttachment = async (file: File): Promise<WorkbenchMediaContentItem> => {
  const url = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader()

    reader.onload = event => {
      if (!event.target || typeof event.target.result !== 'string') {
        reject(new Error('Failed to read file'))
        return
      }
      resolve(event.target.result)
    }

    reader.onerror = () => {
      reject(new Error('Error reading file'))
    }

    reader.readAsDataURL(file)
  })

  return {
    media_type: file.type,
    name: file.name,
    url,
  }
}

export interface ImageAttachmentState {
  promptImage: WorkbenchMediaContentItem | undefined
  imageUploadError: string | undefined
}

export interface ImageAttachmentActions {
  setPromptImage: (image: WorkbenchMediaContentItem | undefined) => void
  setImageUploadError: (error: string | undefined) => void
  attachImage: (e: React.ChangeEvent<HTMLInputElement>) => Promise<void>
  clearImageAttachment: () => void
}

export function useImageAttachment(): ImageAttachmentState & ImageAttachmentActions {
  const [promptImage, setPromptImage] = useState<WorkbenchMediaContentItem | undefined>(undefined)
  const [imageUploadError, setImageUploadError] = useState<string | undefined>(undefined)

  const clearImageAttachment = useCallback(() => {
    setPromptImage(undefined)
    setImageUploadError(undefined)
  }, [])

  const attachImage = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement>) => {
      if (!e.target.files) return
      const file = e.target.files[0]
      e.currentTarget.value = ''
      if (!file) return
      try {
        if (promptImage) {
          throw new Error('Only one image can be attached at a time.')
        }
        if (file.size > IMAGE_ATTACHMENT_SIZE_LIMIT) {
          throw new Error(`File size exceeds ${IMAGE_ATTACHMENT_SIZE_LIMIT / 1000}KB`)
        }

        const mediaItem = await processImageAttachment(file)
        setPromptImage(mediaItem)
        setImageUploadError(undefined)
      } catch (err) {
        setImageUploadError(err instanceof Error ? err.message : String(err))
      }
    },
    [promptImage],
  )

  return {
    promptImage,
    imageUploadError,
    setPromptImage,
    setImageUploadError,
    attachImage,
    clearImageAttachment,
  }
}
