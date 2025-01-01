import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {AlertIcon, LinkIcon, UnlinkIcon} from '@primer/octicons-react'
import {Dialog, IconButton, Link, Spinner, Stack} from '@primer/react'
import {Blankslate, DataTable, Table} from '@primer/react/experimental'
import {useCallback, useEffect, useMemo, useState} from 'react'

import styles from './ManageSharedConversationsDialog.module.css'
import {UnshareConversationDialog} from './UnshareConversationDialog'

interface TableRow {
  id: string
  conversation: string
  lastUpdated: string
  sharedUrl: string
  threadUrl: string
}

interface DialogButton {
  buttonType: 'default' | 'danger' | 'primary'
  content: string
  onClick: () => void
}

interface ManageSharedConversationsDialogProps {
  closeDialog: () => void
}

type BlankslateConfig = {
  result: string
  heading: string
  description: string
  isSpinner?: boolean
}

const formatDate = (dateString: string) => {
  const date = new Date(dateString)
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(date)
}

export const ManageSharedConversationsDialog = ({closeDialog}: ManageSharedConversationsDialogProps) => {
  const manager = useChatManager()
  const state = useChatState()

  const [pageIndex, setPageIndex] = useState(0)
  const [tableData, setTableData] = useState<TableRow[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [showUnshareDialog, setShowUnshareDialog] = useState(false)
  const [selectedConversation, setSelectedConversation] = useState<TableRow | null>(null)
  const [showConfirmationText, setShowConfirmationText] = useState(false)

  const pageSize = 5
  const [isPaginated, setIsPaginated] = useState(pageSize > tableData.length)
  const start = pageIndex * pageSize
  const end = start + pageSize
  const paginatedData = tableData.slice(start, end)

  useEffect(() => {
    const loadSharedThreads = async () => {
      const sharedThreads = await manager.fetchSharedThreads()
      if (sharedThreads) {
        setTableData(
          sharedThreads.map(thread => ({
            id: thread.id,
            conversation: thread.name || 'New conversation',
            lastUpdated: formatDate(thread.updatedAt),
            sharedUrl: `${ssrSafeLocation.origin}/copilot/share/${thread.sharedID}`,
            threadUrl: `${ssrSafeLocation.origin}/copilot/c/${thread.id}`,
          })),
        )
      }
      setIsLoading(false)
    }
    void loadSharedThreads()
  }, [manager])

  useEffect(() => {
    // if we are paginated and on a page that no longer exists, reset to page 0
    if (isPaginated && pageIndex > 0 && tableData.length <= pageIndex * pageSize) {
      setPageIndex(0)
    }
    setIsPaginated(pageSize < tableData.length)
    // Exclude isPaginated because we don't want to rerender the table when the pagination state changes
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tableData, pageIndex, pageSize])

  const handleClose = useCallback(() => {
    closeDialog()
  }, [closeDialog])

  const handleUnshareAllClick = useCallback(async () => {
    // Show confirmation text on the first click
    if (!showConfirmationText) {
      setShowConfirmationText(true)
      return
    }

    setShowConfirmationText(false)
    setIsLoading(true)

    try {
      const result = await manager.unshareAllThreads()
      if (result.ok) {
        setTableData([])
        await manager.fetchThreads()
      }
    } finally {
      setIsLoading(false)
    }
  }, [showConfirmationText, manager])

  const handleOpenUnshareDialog = (conversation: TableRow) => {
    setSelectedConversation(conversation)
    setShowUnshareDialog(true)
  }

  const handleCloseUnshareDialog = async () => {
    setShowUnshareDialog(false)
    setSelectedConversation(null)
    setIsLoading(true)
    const sharedThreads = await manager.fetchSharedThreads()
    if (sharedThreads) {
      setTableData(
        sharedThreads.map(thread => ({
          id: thread.id,
          conversation: thread.name || 'New conversation',
          lastUpdated: formatDate(thread.updatedAt),
          sharedUrl: `${ssrSafeLocation.origin}/copilot/share/${thread.sharedID}`,
          threadUrl: `${ssrSafeLocation.origin}/copilot/c/${thread.id}`,
        })),
      )
    }
    setIsLoading(false)
  }

  const shouldShowBlankslate = isLoading || state.sharedThreadsLoading.state === 'error' || tableData.length === 0

  const footerButtons = useMemo(() => {
    if (!tableData.length) return []

    const cancelButton: DialogButton = {
      buttonType: 'default' as const,
      content: 'Cancel',
      onClick: () => setShowConfirmationText(false),
    }

    const unshareButton: DialogButton = {
      buttonType: 'danger' as const,
      content: 'Unshare all',
      onClick: () => {
        // Only call handleUnshareAllClick if we're in confirmation state
        if (showConfirmationText) {
          void handleUnshareAllClick()
        } else {
          setShowConfirmationText(true)
        }
      },
    }

    // Return appropriate array based on state
    return showConfirmationText ? [cancelButton, unshareButton] : [unshareButton]
  }, [tableData.length, showConfirmationText, handleUnshareAllClick])

  const getConfirmationText = (count: number) => {
    if (count === 1) {
      return 'Are you sure you want to unshare this conversation?'
    }
    return `Are you sure you want to unshare all ${count} conversations?`
  }

  const blankslateContent = useMemo((): BlankslateConfig => {
    if (isLoading) {
      return {
        result: 'loading',
        heading: 'Loading shared conversations',
        description: 'Your shared conversations will appear here.',
        isSpinner: true,
      }
    }

    if (state.sharedThreadsLoading.state === 'error') {
      return {
        result: 'error',
        heading: "We couldn't load the shared conversations",
        description: 'Try again or, if the problem persists, contact support.',
      }
    }

    return {
      result: 'empty',
      heading: 'No shared conversations',
      description: 'Your shared conversations will appear here.',
    }
  }, [isLoading, state.sharedThreadsLoading.state])

  return (
    <Dialog
      title="Manage shared conversations"
      width="xlarge"
      className={styles.dialog}
      position={{narrow: 'fullscreen', regular: 'center'}}
      onClose={handleClose}
      renderFooter={() => {
        if (!footerButtons?.length) return null
        return (
          <Dialog.Footer className={styles.footer}>
            <div className={styles.footerContent}>
              <div className={styles.footerLeft}>
                {showConfirmationText && (
                  <div className={`${styles.confirmationText} ${styles.quickFadeUp}`}>
                    {getConfirmationText(tableData.length)}
                  </div>
                )}
              </div>
              <div className={styles.footerRight}>
                <Dialog.Buttons buttons={footerButtons} />
              </div>
            </div>
          </Dialog.Footer>
        )
      }}
    >
      {shouldShowBlankslate ? (
        <Blankslate>
          <Blankslate.Visual>
            {blankslateContent.isSpinner ? (
              <Stack direction="horizontal" align="center">
                <Spinner size="medium" srText="Loading shared conversations…" />
              </Stack>
            ) : (
              <div className={styles.mutedText}>
                {blankslateContent.result === 'error' ? (
                  <AlertIcon
                    size="medium"
                    className={styles.alertIcon}
                    aria-label="Error loading shared conversations"
                  />
                ) : (
                  <LinkIcon size="medium" aria-label="No shared conversations" />
                )}
              </div>
            )}
          </Blankslate.Visual>
          <Blankslate.Heading>{blankslateContent.heading}</Blankslate.Heading>
          <Blankslate.Description>{blankslateContent.description}</Blankslate.Description>
        </Blankslate>
      ) : (
        <Table.Container>
          <DataTable<TableRow>
            aria-labelledby="manage-shared-conversations"
            cellPadding="normal"
            columns={[
              {
                header: 'Conversation',
                field: 'conversation',
                width: 'growCollapse',
                minWidth: '60%',
                rowHeader: true,
                renderCell: (row: TableRow) => (
                  <Link href={row.threadUrl} className={styles.conversationLink}>
                    {row.conversation}
                  </Link>
                ),
              },
              {
                header: 'Last updated',
                field: 'lastUpdated',
                width: 'growCollapse',
                renderCell: (row: TableRow) => <span className={styles.mutedText}>{row.lastUpdated}</span>,
              },
              {
                id: 'actions',
                width: 'growCollapse',
                align: 'end',
                header: () => (
                  // Visually hidden header for action icons
                  <div className="sr-only">Actions</div>
                ),
                renderCell: (row: TableRow) => {
                  return (
                    <>
                      <div className={styles.actionButtons}>
                        <CopyToClipboardButton
                          textToCopy={row.sharedUrl}
                          onCopy={() => {
                            sendEvent('dotcom_chat.activate', {
                              target: 'COPILOT_COPY_SHARED_CONVERSATION_LINK',
                              mode: 'immersive',
                            })
                          }}
                          ariaLabel="Copy share link"
                        />
                        <IconButton
                          aria-label={`Unshare conversation`}
                          title={`Unshare conversation`}
                          icon={UnlinkIcon}
                          variant="invisible"
                          onClick={() => handleOpenUnshareDialog(row)}
                        />
                      </div>
                    </>
                  )
                },
              },
            ]}
            data={paginatedData}
          />
          {tableData.length > pageSize && (
            <Table.Pagination
              aria-label="Shared conversations pagination"
              pageSize={pageSize}
              defaultPageIndex={pageIndex}
              totalCount={tableData.length}
              onChange={pageInfo => {
                setPageIndex(pageInfo.pageIndex)
              }}
              showPages={false}
            />
          )}
        </Table.Container>
      )}
      {showUnshareDialog && selectedConversation && (
        <UnshareConversationDialog threadId={selectedConversation.id} closeDialog={handleCloseUnshareDialog} />
      )}
    </Dialog>
  )
}
