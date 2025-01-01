import safeStorage from '@github-ui/safe-storage'
import {ChevronDownIcon, ChevronRightIcon, FileSymlinkFileIcon} from '@primer/octicons-react'
import {IconButton, Label, Link} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import {clsx} from 'clsx'
import {useEffect, useState} from 'react'
import styles from './ConversationHeader.module.css'

type ConversationHeaderProps = {
  firstCommentId?: number | null
  isCollapsed: boolean
  isOutdated: boolean
  isResolved: boolean
  line?: number | null
  onNavigateToDiffComment: () => void
  onToggleCollapsed: () => void
  path: string
  rightSideContent?: JSX.Element
  threadId: string
}

export function ConversationHeader({
  firstCommentId,
  isCollapsed: initialIsCollapsed,
  isOutdated,
  isResolved,
  line,
  onToggleCollapsed,
  onNavigateToDiffComment,
  path,
  rightSideContent,
  threadId,
}: ConversationHeaderProps) {
  const safeLocalStorage = safeStorage('localStorage')
  const [isCollapsed, setIsCollapsed] = useState<boolean>(initialIsCollapsed)

  useEffect(() => {
    const storedState = localStorage.getItem(`reviewThreadIsCollapsed_${threadId}`)
    if (storedState !== null) {
      setIsCollapsed(JSON.parse(storedState))
    }
  }, [isCollapsed, threadId])

  const handleToggleCollapsed = () => {
    safeLocalStorage.setItem(`reviewThreadIsCollapsed_${threadId}`, JSON.stringify(!isCollapsed))
    setIsCollapsed((prevIsCollapsed: boolean) => !prevIsCollapsed)
    onToggleCollapsed()
  }

  return (
    <div
      className={clsx(
        'd-flex flex-row flex-items-center px-2 py-1 bgColor-muted rounded-top-2 border-bottom',
        isCollapsed && 'rounded-2',
        isCollapsed && 'border-bottom-0',
      )}
    >
      <IconButton
        aria-label={isCollapsed ? 'Open review comment' : 'Close review comment'}
        icon={isCollapsed ? ChevronRightIcon : ChevronDownIcon}
        size="small"
        variant="invisible"
        onClick={handleToggleCollapsed}
      />
      <h4 className="d-flex flex-items-center flex-1 min-width-0 mr-2 ml-1">
        <Tooltip direction="n" text={path} type="label">
          <Link
            className={clsx(
              styles['file-name-overflow'],
              'd-inline text-mono text-semibold f6 no-wrap overflow-hidden direction-rtl fgColor-default',
            )}
            onClick={onNavigateToDiffComment}
            href={`#r${firstCommentId}`}
            muted
          >
            {/* Ensures path is displayed in left-to-right-order despite container direction being right-to-left */}
            &lrm;{path}
          </Link>
        </Tooltip>
        {!!line && <span className="f6 fgColor-muted text-normal no-wrap ml-2">Line {line}</span>}
      </h4>
      {isResolved && (
        <Label size="large" className="mx-1" variant="done">
          Resolved
        </Label>
      )}
      {isOutdated && !isResolved && (
        <Label size="large" className="mx-1" variant="attention">
          Outdated
        </Label>
      )}
      <IconButton
        as="a"
        aria-label="Jump to the comment in the diff"
        tooltipDirection="se"
        icon={FileSymlinkFileIcon}
        variant="invisible"
        href={`#r${firstCommentId}`}
        onClick={onNavigateToDiffComment}
      />
      {rightSideContent}
    </div>
  )
}
