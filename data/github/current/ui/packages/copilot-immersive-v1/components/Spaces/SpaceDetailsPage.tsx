import {AmbientErrorBanner} from '@github-ui/copilot-chat/components/AmbientErrorBanner'
import {ChatInput} from '@github-ui/copilot-chat/components/ChatInput'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {COPILOT_PATH, threadName} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatThread, CustomCopilot, CustomCopilotId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {
  generateGitHubFileMetadata,
  isIssueOrPrResource,
  spaceSizeExceeded,
} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {
  CustomCopilotNotFoundError,
  CustomCopilotSSOError,
  useFetchCustomCopilot,
} from '@github-ui/custom-copilots/hooks'
import type {
  CustomCopilotFreeTextResource,
  CustomCopilotUploadedTextFileResource,
} from '@github-ui/custom-copilots/types'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {useNavigate} from '@github-ui/use-navigate'
import {
  ClockIcon,
  CommentDiscussionIcon,
  EllipsisIcon,
  KebabHorizontalIcon,
  NoteIcon,
  PaperclipIcon,
  StarFillIcon,
  StarIcon,
  TrashIcon,
} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, CounterLabel, IconButton, Label, Link, RelativeTime} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {useNavigateToNewThread} from '../../hooks/use-navigate-to-new-thread'
import {patchThreadTime} from '../../utils/copilot-immersive-helpers'
import {getVisibilityText} from '../../utils/visibility-helpers'
import {ConversationLoader} from '../ConversationLoader'
import {SpaceNotFoundComponent} from '../SpaceNotFoundComponent'
import {AllAttachmentsDialog} from './AllAttachmentsDialog'
import {AttachmentIcon} from './AttachmentIcon'
import {FullInstructionsDialog} from './FullInstructionsDialog'
import {useStarCopilotSpace} from './hooks/use-star-copilot-space'
import {ReferenceSizeExceededBanner} from './SpaceBanners'
import styles from './SpaceDetailsPage.module.css'
import {SpacesAvatar} from './SpacesAvatar'
import {Tip} from './Tip'

const MAX_VISIBLE_THREADS = 10

export interface SpaceDetailsPageProps {
  customCopilotId: CustomCopilotId
  onChatSubmit?: (text: string) => Promise<void>
  selectedThreadID: string | null
  textAreaRef: React.RefObject<HTMLTextAreaElement>
}

export function SpaceDetailsPage({
  customCopilotId,
  onChatSubmit,
  selectedThreadID,
  textAreaRef,
}: SpaceDetailsPageProps) {
  const {threads, streamingMessage, ambientError} = useChatState()
  const manager = useChatManager()
  const navigateToNewThread = useNavigateToNewThread()
  const [activeMenuConversationId, setActiveMenuConversationId] = useState<string | null>(null)

  const {isPending, data: currentSpacePayload, error} = useFetchCustomCopilot(customCopilotId)
  const [isInstructionsDialogOpen, setIsInstructionsDialogOpen] = useState(false)
  const [isAttachmentsDialogOpen, setIsAttachmentsDialogOpen] = useState(false)

  const items = useMemo(() => {
    if (!currentSpacePayload) return []

    patchThreadTime(threads)
    const filteredThreads = new Map(
      Array.from(threads.entries()).filter(([, thread]) => {
        if (thread.customCopilotOwner) {
          return thread.customCopilotOwner === customCopilotId.owner && thread.customCopilotID === customCopilotId.id
        }
        return thread.customCopilotID === currentSpacePayload.oldId
      }),
    )
    // TODO: prevent page overflows. Need to determine how we handle a lot of threads.
    return manager.sortThreads(filteredThreads).slice(0, MAX_VISIBLE_THREADS)
  }, [threads, customCopilotId, manager, currentSpacePayload])

  useEffect(() => {
    if (currentSpacePayload) {
      manager.dispatch({
        type: 'SET_CUSTOM_COPILOT',
        customCopilot: currentSpacePayload,
      })
    }
    // Preserve image attachments when loading a space
    manager.clearCurrentReferences(['image'])
  }, [currentSpacePayload, manager])

  // Track message submission to avoid clearing references during submission
  const isSubmittingMessage = useRef(false)

  // Clear references when navigating away from SpaceDetails, except during message submission
  useEffect(() => {
    return () => {
      // Only clear references if we're not in the middle of submitting a message
      if (!isSubmittingMessage.current) {
        manager.clearCurrentReferences()
        isSubmittingMessage.current = false
      }
    }
  }, [manager, customCopilotId])

  // Wrapper function to track message submission state
  const handleChatSubmit = useCallback(
    async (content: string) => {
      if (!onChatSubmit) return

      isSubmittingMessage.current = true
      await onChatSubmit(content)
    },
    [onChatSubmit],
  )

  if (error instanceof CustomCopilotNotFoundError) {
    return <SpaceNotFoundComponent />
  } else if (error instanceof CustomCopilotSSOError) {
    return <SpaceNotFoundComponent protectedOrganizations={error.protectedOrganizations} />
  }

  if (isPending || !currentSpacePayload) {
    return <ConversationLoader />
  }

  const referenceSizeExceeded = spaceSizeExceeded(currentSpacePayload)

  const currentSpace = currentSpacePayload
  const visibilityText = getVisibilityText(currentSpace.visibility)

  return (
    <div className={styles.container}>
      <div className={styles.main}>
        <div className={styles.contain}>
          {referenceSizeExceeded && <ReferenceSizeExceededBanner />}

          <div className={styles.header}>
            <SpacesAvatar size={16} color={currentSpace.iconColor} />
            <h3 className={styles.sideTitle}>
              {currentSpace.name}
              <Label className={styles.visibilityLabel} size="small" variant="secondary">
                {visibilityText}
              </Label>
            </h3>
          </div>

          <div className={styles.chatInput}>
            {ambientError && <AmbientErrorBanner ambientError={ambientError} />}
            <ChatInput
              key={selectedThreadID}
              textAreaRef={textAreaRef}
              onSubmit={handleChatSubmit}
              customCopilotId={currentSpace}
              isStreaming={!!streamingMessage}
              size="large"
              disabled={referenceSizeExceeded}
              showModelPicker
              onNewThreadSelected={navigateToNewThread}
            />
          </div>

          <div className={styles.conversations}>
            {items.length > 0 ? (
              <>
                <div className={styles.conversationsContainer}>
                  <nav aria-labelledby="conversations-heading">
                    <div className={styles.conversationsHeader}>
                      <h2 id="conversations-heading" className={styles.conversationsListTitle}>
                        Your last conversations
                      </h2>
                    </div>
                    <ul role="menu" className={styles.conversationsList}>
                      {items.map(conversation => (
                        <ConversationItem
                          key={conversation.id}
                          conversation={conversation}
                          activeMenuConversationId={activeMenuConversationId}
                          setActiveMenuConversationId={setActiveMenuConversationId}
                        />
                      ))}
                    </ul>
                  </nav>
                </div>
                {currentSpace.ownerIsOrg && <Tip>Your conversations stay private when you share a space.</Tip>}
              </>
            ) : (
              <div className={styles.noConversations}>
                <NoConversationsPlaceholder />
              </div>
            )}
          </div>
        </div>

        <aside className={styles.meta}>
          <InfoSection copilotSpace={currentSpace} />
          <MetadataSection
            copilotSpace={currentSpace}
            setInstructionsDialogOpen={setIsInstructionsDialogOpen}
            setAttachmentsDialogOpen={setIsAttachmentsDialogOpen}
          />
          {currentSpace.generalInstructions ||
          currentSpace.starredUsers.length > 0 ||
          currentSpace.resources.length > 0 ? (
            <>
              {currentSpace.generalInstructions && (
                <InstructionsSection
                  copilotSpace={currentSpace}
                  isDialogOpen={isInstructionsDialogOpen}
                  setDialogOpen={setIsInstructionsDialogOpen}
                />
              )}
              {currentSpace.starredUsers.length > 0 && <StarredSection copilotSpace={currentSpace} />}
              {currentSpace.resources.length > 0 && (
                <AttachmentsSection
                  copilotSpace={currentSpace}
                  isDialogOpen={isAttachmentsDialogOpen}
                  setDialogOpen={setIsAttachmentsDialogOpen}
                />
              )}
            </>
          ) : (
            <section className={clsx(styles.noConversations, styles.desktopOnly)}>
              <div className={styles.contextPlaceholder}>
                <PaperclipIcon size={24} />

                <div className={styles.conversationsPlaceholderText}>
                  This space doesn’t have any instructions or attachments yet
                </div>
              </div>
            </section>
          )}
        </aside>
      </div>
    </div>
  )
}

interface ConversationItemProps {
  conversation: CopilotChatThread
  activeMenuConversationId: string | null
  setActiveMenuConversationId: (id: string | null) => void
}

function ConversationItem({
  conversation,
  activeMenuConversationId,
  setActiveMenuConversationId,
}: ConversationItemProps) {
  const navigate = useNavigate()
  const manager = useChatManager()

  const name = threadName(conversation)
  const threadUrl = `${COPILOT_PATH}/c/${conversation.id}`
  // TODO: is it worth it to fetch the last message?
  // Might cause a performance issue if we're fetching each thread messages
  // const description = ''

  function handleDeleteThread() {
    void manager.deleteThread(conversation)
  }

  // TODO: We shouldn't allow the whole li to be clickable
  // Interfere with the ActionMenu
  return (
    <li
      role="menuitem"
      onClick={() => {
        navigate(threadUrl)
      }}
      onKeyDown={e => {
        if (e.key === 'Enter') {
          navigate(threadUrl)
        }
      }}
      className={clsx(styles.conversationItem, activeMenuConversationId !== null && styles.conversationItemMenuOpen)}
    >
      <div className={styles.conversationItemLeftColumn}>
        <div className={styles.conversationName}>{name}</div>
        {/* <div className={styles.conversationKickoffMessage}>{description}</div> */}
        <div className={styles.conversationTimestamp}>
          <ClockIcon /> <RelativeTime format="relative" prefix="" date={new Date(conversation.updatedAt)} />
        </div>
      </div>

      <ActionMenu
        open={activeMenuConversationId === conversation.id}
        onOpenChange={isOpen => {
          setActiveMenuConversationId(isOpen ? conversation.id : null)
        }}
      >
        <ActionMenu.Anchor>
          <IconButton
            variant="invisible"
            aria-label="Conversation options"
            icon={KebabHorizontalIcon}
            onClick={e => {
              e.stopPropagation()
            }}
          />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay onClick={e => e.stopPropagation()} align="end">
          <ActionList>
            <ActionList.Item variant="danger" onSelect={handleDeleteThread}>
              <ActionList.LeadingVisual>
                <TrashIcon />
              </ActionList.LeadingVisual>
              Delete
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </li>
  )
}

function NoConversationsPlaceholder() {
  return (
    <section className={styles.noConversations}>
      <div className={styles.conversationsPlaceholder}>
        <CommentDiscussionIcon size={24} />

        <div className={styles.conversationsPlaceholderText}>Start your first conversation using the input above</div>
      </div>
    </section>
  )
}

function InfoSection({copilotSpace}: {copilotSpace: CustomCopilot}) {
  const MAX_DESCRIPTION_LENGTH = 140

  const [descriptionIsExpanded, setDescriptionIsExpanded] = useState(false)
  const descriptionExceedsLimit = (copilotSpace.description?.length ?? 0) > MAX_DESCRIPTION_LENGTH
  const isDescriptionTruncated = descriptionExceedsLimit && !descriptionIsExpanded

  const {starCopilotSpace} = useStarCopilotSpace(copilotSpace)

  return (
    <section className={styles.info}>
      <div className={clsx(styles.sideSectionHeader, styles.desktopOnly)}>
        <h4 className={styles.sideSectionTitle}>About</h4>
      </div>
      <p className={styles.infoDescription}>
        {copilotSpace.description ? (
          (isDescriptionTruncated
            ? copilotSpace.description.slice(0, MAX_DESCRIPTION_LENGTH)
            : copilotSpace.description
          ).replaceAll('\n\n', '\n')
        ) : (
          <span className={clsx(styles.noDescription, styles.desktopOnly)}>No description</span>
        )}
        {copilotSpace.description && isDescriptionTruncated && (
          <button
            type="button"
            aria-label="Expand description"
            className={styles.descriptionExpander}
            onClick={() => setDescriptionIsExpanded(true)}
          >
            <EllipsisIcon size={16} />
          </button>
        )}
      </p>

      <Button
        className={styles.starButton}
        block
        onClick={() => void starCopilotSpace({starred: !copilotSpace.starred})}
        leadingVisual={copilotSpace.starred ? <StarFillIcon className={styles.starFillIcon} /> : <StarIcon />}
        variant="default"
      >
        {copilotSpace.starred ? 'Starred' : 'Star'}
      </Button>
    </section>
  )
}

function MetadataSection({
  copilotSpace,
  setInstructionsDialogOpen,
  setAttachmentsDialogOpen,
}: {
  copilotSpace: CustomCopilot
  setInstructionsDialogOpen: (open: boolean) => void
  setAttachmentsDialogOpen: (open: boolean) => void
}) {
  return (
    <ActionList variant="full" className={styles.actionListOffset}>
      <ActionList.LinkItem href={`/${copilotSpace.owner}`}>
        <ActionList.LeadingVisual>
          <GitHubAvatar size={16} square={copilotSpace.ownerIsOrg} src={copilotSpace.ownerAvatar} />
        </ActionList.LeadingVisual>
        <span className="fgColor-muted">
          Owned by <strong className="text-semibold">{copilotSpace.owner}</strong>
        </span>
      </ActionList.LinkItem>
      {copilotSpace.generalInstructions && (
        <ActionList.Item onSelect={() => setInstructionsDialogOpen(true)} className={styles.mobileOnly}>
          <ActionList.LeadingVisual>
            <NoteIcon />
          </ActionList.LeadingVisual>
          <span className="fgColor-muted">View instructions</span>
        </ActionList.Item>
      )}
      {copilotSpace.resources.length > 0 && (
        <ActionList.Item onSelect={() => setAttachmentsDialogOpen(true)} className={styles.mobileOnly}>
          <ActionList.LeadingVisual>
            <PaperclipIcon />
          </ActionList.LeadingVisual>
          <span className="fgColor-muted">
            {copilotSpace.resources.length} attachment{copilotSpace.resources.length > 1 ? 's' : ''}
          </span>
        </ActionList.Item>
      )}
    </ActionList>
  )
}

function InstructionsSection({
  copilotSpace,
  isDialogOpen,
  setDialogOpen,
}: {
  copilotSpace: CustomCopilot
  isDialogOpen: boolean
  setDialogOpen: (open: boolean) => void
}) {
  const returnFocusRef = useRef<HTMLButtonElement>(null)

  return (
    <>
      <SideSection title="Instructions">
        <p className={styles.instructionsText}>{(copilotSpace.generalInstructions || '').replaceAll('\n\n', '\n')}</p>
        <Link
          className={styles.instructionsLink}
          as="button"
          ref={returnFocusRef}
          onClick={() => setDialogOpen(true)}
          aria-haspopup="dialog"
          aria-expanded={isDialogOpen}
        >
          View full instructions
        </Link>
      </SideSection>

      {isDialogOpen && (
        <FullInstructionsDialog
          copilotSpace={copilotSpace}
          onClose={() => setDialogOpen(false)}
          returnFocusRef={returnFocusRef}
        />
      )}
    </>
  )
}

function AttachmentsSection({
  copilotSpace,
  isDialogOpen,
  setDialogOpen,
}: {
  copilotSpace: CustomCopilot
  isDialogOpen: boolean
  setDialogOpen: (open: boolean) => void
}) {
  const [initialDialogAttachment, setInitialDialogAttachment] = useState<
    CustomCopilotFreeTextResource | CustomCopilotUploadedTextFileResource | null
  >(null)
  const returnFocusRef = useRef<HTMLButtonElement>(null)

  const firstFiveAttachments = copilotSpace.resources.slice(0, 5)
  return (
    <>
      <SideSection title="Attachments" count={copilotSpace.resources.length}>
        <ActionList variant="full" className={styles.actionListOffset}>
          {firstFiveAttachments.map(resource => {
            if (resource.type === 'free_text' || resource.type === 'uploaded_text_file') {
              return (
                <ActionList.Item
                  key={resource.id}
                  onSelect={() => {
                    setInitialDialogAttachment(resource)
                    setDialogOpen(true)
                  }}
                >
                  <ActionList.LeadingVisual>
                    <AttachmentIcon attachment={resource} />
                  </ActionList.LeadingVisual>
                  <span className={styles.lineClamp}>{resource.name}</span>
                </ActionList.Item>
              )
            }

            const attachmentClassName = isIssueOrPrResource(resource) ? 'fgColor-success' : ''
            const {fileName, fileUrl} =
              resource.type === 'github_file'
                ? generateGitHubFileMetadata(resource)
                : {fileName: resource.title, fileUrl: resource.url}

            return (
              <ActionList.LinkItem key={resource.id} href={fileUrl}>
                <ActionList.LeadingVisual>
                  <AttachmentIcon attachment={resource} className={attachmentClassName} />
                </ActionList.LeadingVisual>
                <span className={styles.lineClamp}>{fileName}</span>
              </ActionList.LinkItem>
            )
          })}
        </ActionList>

        <Link
          className={styles.attachmentsLink}
          as="button"
          ref={returnFocusRef}
          onClick={() => setDialogOpen(true)}
          aria-haspopup="dialog"
          aria-expanded={isDialogOpen}
        >
          View all attachments
        </Link>
      </SideSection>
      {isDialogOpen && (
        <AllAttachmentsDialog
          copilotSpace={copilotSpace}
          initialAttachment={initialDialogAttachment}
          onClose={() => {
            setInitialDialogAttachment(null)
            setDialogOpen(false)
          }}
          returnFocusRef={returnFocusRef}
        />
      )}
    </>
  )
}

function StarredSection({copilotSpace}: {copilotSpace: CustomCopilot}) {
  return (
    <>
      <SideSection title="Starred by" count={copilotSpace.starredUsers.length}>
        <div>
          {copilotSpace.starredUsers.map(user => (
            <GitHubAvatar className="mr-2" key={user.login} size={32} src={user.avatarUrl} alt={user.login} />
          ))}
        </div>
      </SideSection>
    </>
  )
}

function SideSection({title, count, children}: {title: string; count?: number; children: React.ReactNode}) {
  return (
    <div className={clsx(styles.sideSection, styles.desktopOnly)}>
      <div className={styles.sideSectionHeader}>
        <h4 className={styles.sideSectionTitle}>
          {title} {!!count && <CounterLabel>{count}</CounterLabel>}
        </h4>
      </div>
      {children}
    </div>
  )
}
