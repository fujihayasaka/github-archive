import {BingIcon} from '@github-ui/copilot-reference-preview/components/WebSearchReferencePreview'
import {
  BookIcon,
  CodeIcon,
  CodeSquareIcon,
  CommentDiscussionIcon,
  FileDiffIcon,
  FileDirectoryFillIcon,
  FileIcon,
  GitCommitIcon,
  GitMergeIcon,
  GitPullRequestClosedIcon,
  GitPullRequestDraftIcon,
  GitPullRequestIcon,
  GlobeIcon,
  IssueClosedIcon,
  IssueDraftIcon,
  IssueOpenedIcon,
  MarkdownIcon,
  NoteIcon,
  RepoIcon,
  SkipIcon,
  XIcon,
} from '@primer/octicons-react'
import {IconButton, Spinner} from '@primer/react'
import {SkeletonText} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {forwardRef, type KeyboardEventHandler, type MouseEventHandler, useId} from 'react'

import {isDocset, referenceID, referenceName, referenceURL} from '../utils/copilot-chat-helpers'
import type {CopilotChatMessage, CopilotChatReference} from '../utils/copilot-chat-types'
import {useChatStateLens, useChatStateValue} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {docLanguages} from '../utils/language-info'
import {FigmaIcon} from './icons/FigmaIcon'
import styles from './ReferenceToken.module.css'
import {VersionName} from './VersionName'

export interface ReferenceTokenProps {
  reference: CopilotChatReference
  message?: CopilotChatMessage
  onClick?: (reference: CopilotChatReference, event?: React.MouseEvent<HTMLAnchorElement>) => void
  onRemove?: () => void
  size: 'medium' | 'small'
  getReferenceVersion?: (reference: CopilotChatReference) => number | undefined
}

export const ReferenceToken = forwardRef<HTMLAnchorElement, ReferenceTokenProps>(function ReferenceToken(
  {reference, message, onClick, onRemove, size, getReferenceVersion},
  ref,
) {
  // We are copying the functionality of Primer's `Token` in that we have a focusable parent but do not allow focusing
  // close the button. This allows us to create a list of references where each reference is only one focusable item,
  // a pattern that's easier to navigate and avoids nested focusable elements.
  // A deviation from the Primer pattern is that we still do this for non-interactive tokens where we don't have a URL
  // to navigate to. This is useful for consistency across the entire list, even though these tokens don't actually
  // do anything when activated.

  const onKeyDown: KeyboardEventHandler<HTMLAnchorElement> = event => {
    if (!onRemove) return

    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (event.key === 'Delete' || event.key === 'Backspace') {
      event.preventDefault()
      onRemove()
    }
  }

  const manager = useChatManager()
  const isImmersive = useChatStateLens(s => s.mode === 'immersive')
  const threadID = useChatStateValue('selectedThreadID')

  const clickHandler: MouseEventHandler<HTMLAnchorElement> = event => {
    if (onClick) {
      onClick(reference, event)
      if (event.defaultPrevented) return
    }

    // Assert as immersive already has its own onClick handler
    if (isImmersive) return

    // This opens the chat window in the new tab after the link navigates so the user experience is not disrupted
    if (reference.type === 'issue' || reference.type === 'pull-request' || reference.type === 'discussion') {
      window.open(reference.url, '_blank')
      self.focus()
    }

    // Open in immersive as assistive does not support these previews
    if (['file', 'thread-scoped-file'].includes(reference.type)) {
      let immersivePath = threadID ? `/copilot/c/${threadID}` : '/copilot'
      immersivePath += `?reference_id=${referenceID(reference)}`
      if (message) {
        immersivePath += `&message_index=${message.messageIndex}`
      }
      window.open(immersivePath, '_blank')
      return
    }

    // We can't preview some types of references, so we just let the link navigate
    if (['repository', 'folder', 'docset', 'third-party', 'image', 'issue', 'pull-request'].includes(reference.type))
      return

    event.preventDefault()
    manager.selectReference(reference)
  }

  const isDocsetChat = isDocset(useChatStateValue('currentTopic'))
  const Icon = iconForReference(reference, isDocsetChat)

  const descriptionId = useId()

  const version = getReferenceVersion?.(reference)

  return (
    <>
      <a
        href={referenceURL(reference)}
        className={clsx(styles.referenceToken, size === 'small' && styles.small)}
        onKeyDown={onKeyDown}
        onClick={clickHandler}
        ref={ref}
        aria-describedby={onRemove && descriptionId}
      >
        {Icon && (
          <Icon
            size="small"
            className={clsx(
              styles.icon,
              Icon === IssueOpenedIcon && styles.openIcon,
              Icon === GitPullRequestIcon && styles.openIcon,
              Icon === IssueClosedIcon && styles.closedIcon,
              Icon === GitPullRequestClosedIcon && styles.pullRequestClosedIcon,
              Icon === GitMergeIcon && styles.pullRequestMergedIcon,
            )}
          />
        )}
        {reference.type === 'loading' ? (
          <span className={styles.loadingName}>
            <SkeletonText aria-label={referenceName(reference)} />
          </span>
        ) : (
          <span className={styles.name}>{referenceName(reference)}</span>
        )}
        {version !== undefined && (
          <span className={styles.trailingVisual}>
            <VersionName version={version} />
          </span>
        )}
        {onRemove && <RemoveReferenceTokenButton size={size} onRemove={onRemove} descriptionId={descriptionId} />}
      </a>
    </>
  )
})

function iconForIssueReference(reference: CopilotChatReference) {
  if (reference.type !== 'issue') {
    return undefined
  }

  switch (reference.state) {
    case 'open':
      return IssueOpenedIcon
    case 'closed':
      return IssueClosedIcon
    case 'not_planned':
      return SkipIcon
    default:
      return IssueOpenedIcon
  }
}

function iconForPullRequestReference(reference: CopilotChatReference) {
  if (reference.type !== 'pull-request') {
    return undefined
  }

  if (reference.draft && reference.state === 'open') {
    return GitPullRequestDraftIcon
  }

  switch (reference.state) {
    case 'open':
      return GitPullRequestIcon
    case 'closed':
      return GitPullRequestClosedIcon
    case 'merged':
      return GitMergeIcon
    default:
      return GitPullRequestIcon
  }
}

function iconForWebSearchReference(reference: CopilotChatReference) {
  if (reference.type !== 'web-search-result') {
    return undefined
  }

  switch (reference.reference_type) {
    case 'bing_search':
      return BingIcon
    default:
      return GlobeIcon
  }
}

export function iconForReference(reference: CopilotChatReference, isDocsetChat: boolean) {
  switch (reference.type) {
    case 'figma':
      return StylizedFigmaIcon
    case 'file':
      return FileIcon
    case 'folder':
      return FileDirectoryFillIcon
    case 'file-diff':
      return FileDiffIcon
    case 'snippet':
      return isDocsetChat &&
        'languageName' in reference &&
        reference.languageName &&
        docLanguages.has(reference.languageName)
        ? BookIcon
        : CodeIcon
    case 'repository':
      return RepoIcon
    case 'symbol':
      return CodeSquareIcon
    case 'docset':
      return BookIcon
    case 'commit':
      return GitCommitIcon
    case 'pull-request':
      return iconForPullRequestReference(reference)
    case 'repo-instructions':
    case 'org-instructions':
      return NoteIcon
    case 'issue':
      return iconForIssueReference(reference)
    case 'draft-issue':
      return IssueDraftIcon
    case 'discussion':
      return CommentDiscussionIcon
    case 'web-search-result':
      return iconForWebSearchReference(reference)
    case 'thread-scoped-file':
      return 'language' in reference && docLanguages.has(reference.language) ? MarkdownIcon : CodeIcon
    case 'loading':
      return Spinner
    default:
      return undefined
  }
}

function StylizedFigmaIcon() {
  return (
    <div className={styles.figmaIconOuter}>
      <FigmaIcon className={styles.figmaIcon} />
    </div>
  )
}

export const RemoveReferenceTokenButton = ({
  size,
  onRemove,
  descriptionId,
  onMouseOver,
  onMouseLeave,
}: {
  size: 'medium' | 'small'
  onRemove: () => void
  descriptionId: string
  onMouseOver?: MouseEventHandler<HTMLButtonElement>
  onMouseLeave?: MouseEventHandler<HTMLButtonElement>
}) => {
  return (
    <>
      <IconButton
        tabIndex={-1}
        aria-hidden
        size={size}
        icon={XIcon}
        aria-label="Remove"
        onClick={e => {
          // avoid activating the containing element
          e.stopPropagation()
          e.preventDefault()
          onRemove()
        }}
        tooltipDirection="n"
        variant="invisible"
        className={styles.removeButton}
        onMouseOver={onMouseOver}
        onMouseLeave={onMouseLeave}
      />
      <span hidden id={descriptionId}>
        press backspace or delete to remove
      </span>
    </>
  )
}
