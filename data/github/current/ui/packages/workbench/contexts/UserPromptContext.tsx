import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {createContext, useContext, useEffect, useMemo, useState} from 'react'

import {useImageAttachment} from '../hooks/use-image-attachment'
import type {WorkbenchMediaContentItem} from '../types/workbench-types'

export type UserPromptContext = {
  promptImage: WorkbenchMediaContentItem | undefined
  setPromptImage: (image: WorkbenchMediaContentItem | undefined) => void
  promptText: string
  setPromptText: (text: string) => void
  promptError: string | null
  setPromptError: (error: string | null) => void
  imageUploadError: string | undefined
  setImageUploadError: (error: string | undefined) => void
  attachImage: (e: React.ChangeEvent<HTMLInputElement>) => Promise<void>
  clearImageAttachment: () => void
}
export function UserPromptContextProvider({children}: {children: React.ReactNode}) {
  const {promptImage, setPromptImage, imageUploadError, setImageUploadError, clearImageAttachment, attachImage} =
    useImageAttachment()
  const [promptText, setPromptText] = useState<string>('')
  const [promptError, setPromptError] = useState<string | null>(null)

  const [pendingSubmission, setPendingSubmission] = useLocalStorage<
    | {
        promptText: string | undefined
        promptImage: WorkbenchMediaContentItem | undefined
      }
    | undefined
  >('workbench-pending-submission', undefined)

  useEffect(() => {
    if (pendingSubmission) {
      setPromptText(pendingSubmission.promptText || '')
      setPromptImage(pendingSubmission.promptImage)
      setPendingSubmission(undefined)
    }
  }, [pendingSubmission, promptImage, promptText, setPendingSubmission, setPromptImage])

  const value = useMemo(
    () => ({
      promptImage,
      setPromptImage,
      promptText,
      setPromptText,
      promptError,
      setPromptError,
      imageUploadError,
      setImageUploadError,
      attachImage,
      clearImageAttachment,
    }),
    [
      attachImage,
      clearImageAttachment,
      imageUploadError,
      promptImage,
      promptText,
      setImageUploadError,
      setPromptImage,
      promptError,
      setPromptError,
    ],
  )

  return <UserPromptContext.Provider value={value}>{children}</UserPromptContext.Provider>
}

export const UserPromptContext = createContext<UserPromptContext | undefined>(undefined)

export function useUserPromptContext() {
  const context = useContext(UserPromptContext)
  if (!context) {
    throw new Error('useUserPromptContext must be used within a UserPromptContextProvider')
  }

  return context
}
