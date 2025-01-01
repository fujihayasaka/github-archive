import {useContext} from 'react'

import type {PreviewableContent} from '../utils/content-preview-types'
import {ContentPreviewContext} from '../utils/ContentPreviewContext'
import {sendContentPreviewEvent} from '../utils/telemetry'

type useContentPreviewHookValues = {
  previewItems: PreviewableContent[]
  activePath: string | undefined
  setActivePath: (path: string | undefined) => void
  updatePreviewItems: (newPreviewItems: PreviewableContent[], index?: number) => void
  appendPreviewItem: (newFile: PreviewableContent) => void
  clearPreviewItems: () => void
}

export const useContentPreview = (): useContentPreviewHookValues => {
  const context = useContext(ContentPreviewContext)
  if (!context) {
    throw new Error('useContentPreview must be used within a ContentPreviewContext')
  }
  const {previewItems, setPreviewItems, activePath, setActivePath} = context

  const clearPreviewItems = () => {
    setPreviewItems([])
  }

  const appendPreviewItem = (newItem: PreviewableContent, setActive: boolean = true) => {
    setPreviewItems(prevState => {
      if (prevState.find(file => file.path === newItem.path)) {
        return prevState
      } else {
        return [...prevState, newItem]
      }
    })

    if (setActive) {
      setActivePath(newItem.path)
    }

    sendContentPreviewEvent('dotcom_chat.activate', newItem, {
      target: 'RICH_CONTENT_FILE_OPEN',
    })
  }

  const updatePreviewItems = (newItems: PreviewableContent[]) => {
    setPreviewItems(newItems)
  }

  return {
    previewItems,
    activePath,
    setActivePath,
    updatePreviewItems,
    appendPreviewItem,
    clearPreviewItems,
  }
}
