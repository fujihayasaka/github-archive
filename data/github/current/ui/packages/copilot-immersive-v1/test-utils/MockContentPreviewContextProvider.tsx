import {noop} from '@github-ui/noop'
import {useMemo} from 'react'

import {ContentPreviewContext} from '../components/ContentPreview/ContentPreviewContext'

export function MockContentPreviewContextProvider({children}: {children: React.ReactNode}) {
  return (
    <ContentPreviewContext.Provider
      value={useMemo(
        () => ({
          items: new Map(),
          versionedItems: new Map(),
          openItems: [],
          openItemsBeforeSubthreadChange: [],
          messagesBeforeSubthreadChange: [],
          previewPaneOpen: false,
          selectedItem: undefined,
          updateItem: noop,
          setOpenItemsBeforeSubthreadChange: noop,
          setMessagesBeforeSubthreadChange: noop,
          openItem: noop,
          closeItem: noop,
          closeAllItems: noop,
          openPreviewPane: noop,
          closePreviewPane: noop,
          removeItems: noop,
          showLoadingState: false,
          enableLoadingState: noop,
          disableLoadingState: noop,
          closeAll: noop,
        }),
        [],
      )}
    >
      {children}
    </ContentPreviewContext.Provider>
  )
}
