import {createContext, useContext} from 'react'

interface ContentPreviewBlockContext {
  messageId: string
}

export const ContentPreviewBlockContext = createContext<ContentPreviewBlockContext | null>(null)

export const useContentPreviewBlockContext = () => {
  const context = useContext(ContentPreviewBlockContext)

  if (!context) throw new Error('Missing required ContentPreviewBlockContext provider.')

  return context
}
