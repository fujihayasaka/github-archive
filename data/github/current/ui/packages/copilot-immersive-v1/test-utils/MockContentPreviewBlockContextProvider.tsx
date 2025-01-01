import type React from 'react'
import {useMemo} from 'react'

import {ContentPreviewBlockContext} from '../markdown-extensions/ContentPreviewBlockContext'

export function MockContentPreviewBlockContextProvider({children}: {children: React.ReactNode}) {
  const value = useMemo(
    () => ({
      messageId: 'messageId',
      messageIndex: 0,
      messageTimestamp: 'messageTimestamp',
      autoOpenPreviewPane: false,
      markdown: 'markdown',
      hasAutoOpenedPreviewPaneRef: {current: false},
    }),
    [],
  )

  return <ContentPreviewBlockContext.Provider value={value}>{children}</ContentPreviewBlockContext.Provider>
}
