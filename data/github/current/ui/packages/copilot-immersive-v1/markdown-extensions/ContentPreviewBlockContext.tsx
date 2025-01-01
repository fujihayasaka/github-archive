import {createContext, useContext} from 'react'

export interface ContentPreviewBlockContext {
  messageId: string
  messageIndex: number
  messageTimestamp: string
  autoOpenPreviewPane: boolean
  markdown: string
  hasAutoOpenedPreviewPaneRef: React.MutableRefObject<boolean>
}

export const ContentPreviewBlockContext = createContext<ContentPreviewBlockContext | null>(null)

export const useContentPreviewBlockContext = () => {
  const context = useContext(ContentPreviewBlockContext)

  if (!context) throw new Error('Missing required ContentPreviewBlockContext provider.')

  return context
}
