import {clsx} from 'clsx'
import {ChevronDownIcon, ChevronRightIcon, AlertIcon} from '@primer/octicons-react'

import styles from './ToolHeader.module.css'

export interface ToolHeaderProps {
  /**
   * Indicates whether the file is in a collapsed state
   */
  isCollapsed?: boolean
  /**
   * Title details of tool-driven titles
   */
  title: string
  /**
   * The path to the file, if part of the args
   */
  path?: string
  /**
   * Indicates whether the tool is in an error state
   */
  isError?: boolean
}

export function ToolHeader({title, path, isCollapsed, isError = false}: ToolHeaderProps) {
  return (
    <summary
      className={clsx(
        styles.headerButton,
        'Button width-full fgColor-muted flex-justify-start height-full Button--invisible p-2 rounded-0 text-normal d-flex flex-items-center gap-2 bg-subtle',
        !isCollapsed && 'border-bottom',
      )}
      aria-label={isCollapsed ? 'Expand tool' : 'Collapse tool'}
    >
      {isCollapsed ? <ChevronRightIcon className="ml-1" /> : <ChevronDownIcon className="ml-1" />}
      <div className="d-flex gap-2 fgColor-muted flex-items-center overflow-hidden flex-1">
        <span className={styles.headerButtonText}>
          {title}
          {path ? <span className={clsx('text-mono fgColor-default', styles.path)}> {path}</span> : null}
        </span>
        {isError && <AlertIcon size={16} className="color-fg-attention flex-shrink-0" />}
      </div>
    </summary>
  )
}
