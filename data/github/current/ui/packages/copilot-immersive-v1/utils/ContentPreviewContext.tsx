import {createContext} from 'react'

import type {PreviewableContent} from '../utils/content-preview-types'

export type ContentPreviewContextProps = {
  previewItems: PreviewableContent[]
  setPreviewItems: React.Dispatch<React.SetStateAction<PreviewableContent[]>>
  activePath: string | undefined
  setActivePath: React.Dispatch<React.SetStateAction<string | undefined>>
}

export const ContentPreviewContext = createContext<ContentPreviewContextProps | undefined>(undefined)
