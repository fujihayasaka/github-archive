import {isDocset, referenceName, referenceURL} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {
  BookIcon,
  CodeIcon,
  CodeSquareIcon,
  FileDiffIcon,
  FileIcon,
  GitCommitIcon,
  GitPullRequestIcon,
  NoteIcon,
  RepoIcon,
  XIcon,
} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {clsx} from 'clsx'
import {forwardRef, type KeyboardEventHandler, type MouseEventHandler, useId} from 'react'

import {useChatStateLens, useChatStateValue} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {docLanguages} from '../utils/language-info'
import styles from './ReferenceToken.module.css'

interface ReferenceTokenProps {
  reference: CopilotChatReference
  onRemove?: () => void
  size: 'medium' | 'small'
}

export const ReferenceToken = forwardRef<HTMLAnchorElement, ReferenceTokenProps>(function ReferenceToken(
  {reference, onRemove, size},
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
  const onClick: MouseEventHandler<HTMLAnchorElement> = event => {
    // Immersive doesn't (yet) support previewing
    if (isImmersive) return

    // We can't preview some types of references, so we just let the link navigate
    if (['repository', 'docset', 'third-party'].includes(reference.type)) return

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
        onClick={onClick}
        ref={ref}
        aria-describedby={onRemove && descriptionId}
      >
        {Icon && <Icon size="small" className={styles.icon} />}
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

export function iconForReference(reference: CopilotChatReference, isDocsetChat: boolean) {
  switch (reference.type) {
    case 'file':
      return FileIcon
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
    default:
      return undefined
  }
}
