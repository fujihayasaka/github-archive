import {
  BookIcon,
  CodeIcon,
  CodeSquareIcon,
  FileDiffIcon,
  FileDirectoryFillIcon,
  FileIcon,
  GitCommitIcon,
  GitPullRequestIcon,
  ImageIcon,
  IssueClosedIcon,
  IssueOpenedIcon,
  NoteIcon,
  RepoIcon,
  SkipIcon,
  XIcon,
} from '@primer/octicons-react'
import {IconButton, Spinner} from '@primer/react'
import {clsx} from 'clsx'
import {forwardRef, type KeyboardEventHandler, type MouseEventHandler, useId} from 'react'

import {isDocset, referenceName, referenceURL} from '../utils/copilot-chat-helpers'
import type {CopilotChatReference} from '../utils/copilot-chat-types'
import {useChatStateLens, useChatStateValue} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {docLanguages} from '../utils/language-info'
import {FigmaIcon} from './icons/FigmaIcon'
import styles from './ReferenceToken.module.css'

export interface ReferenceTokenProps {
  reference: CopilotChatReference
  onClick?: (event: React.MouseEvent<HTMLAnchorElement>, reference: CopilotChatReference) => void
  onRemove?: () => void
  size: 'medium' | 'small'
}

export const ReferenceToken = forwardRef<HTMLAnchorElement, ReferenceTokenProps>(function ReferenceToken(
  {reference, onClick, onRemove, size},
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
  const clickHandler: MouseEventHandler<HTMLAnchorElement> = event => {
    if (onClick) {
      onClick(event, reference)
      if (event.defaultPrevented) return
    }

    // Immersive doesn't (yet) support previewing
    if (isImmersive) return

    // This opens the chat window in the new tab after the link navigates so the user experience is not disrupted
    if (reference.type === 'issue') {
      window.open(reference.url, '_blank')
      self.focus()
    }

    // We can't preview some types of references, so we just let the link navigate
    if (['repository', 'folder', 'docset', 'third-party', 'image', 'issue'].includes(reference.type)) return

    event.preventDefault()
    manager.selectReference(reference)
  }

  const isDocsetChat = isDocset(useChatStateValue('currentTopic'))
  const Icon = iconForReference(reference, isDocsetChat)

  const descriptionId = useId()

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
              Icon === IssueClosedIcon && styles.closedIcon,
            )}
          />
        )}
        <span className={styles.name}>{referenceName(reference)}</span>
        {onRemove && (
          <>
            <IconButton
              tabIndex={-1}
              aria-hidden
              size={size}
              icon={XIcon}
              aria-label="Remove"
              onClick={e => {
                // avoid activating the containing link
                e.stopPropagation()
                e.preventDefault()
                onRemove()
              }}
              tooltipDirection="n"
              variant="invisible"
              className={styles.removeButton}
            />
            <span hidden id={descriptionId}>
              press backspace or delete to remove
            </span>
          </>
        )}
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
      return isDocsetChat && reference.languageName && docLanguages.has(reference.languageName) ? BookIcon : CodeIcon
    case 'repository':
      return RepoIcon
    case 'symbol':
      return CodeSquareIcon
    case 'docset':
      return BookIcon
    case 'commit':
      return GitCommitIcon
    case 'pull-request':
      return GitPullRequestIcon
    case 'repo-instructions':
      return NoteIcon
    case 'image':
      return reference.attachment.isLoaded ? ImageIcon : Spinner
    case 'issue':
      return iconForIssueReference(reference)
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
