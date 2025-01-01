import React, {type ReactNode, useState} from 'react'

import type {PreviewableContent} from '../../utils/content-preview-types'
import {ContentPreviewContext} from '../../utils/ContentPreviewContext'

export type ContentPreviewProviderProps = {
  children: ReactNode
}

export const ContentPreviewProvider: React.FC<ContentPreviewProviderProps> = ({children}) => {
  const [previewItems, setPreviewItems] = useState<PreviewableContent[]>([])
  const [activePath, setActivePath] = useState<string | undefined>(undefined)
  const value = React.useMemo(
    () => ({previewItems, setPreviewItems, activePath, setActivePath}),
    [previewItems, activePath],
  )

  return <ContentPreviewContext.Provider value={value}>{children}</ContentPreviewContext.Provider>
}
