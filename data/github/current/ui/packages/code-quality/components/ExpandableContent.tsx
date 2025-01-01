import {ChevronDownIcon, ChevronUpIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import type {ReactNode} from 'react'
import {useState} from 'react'

import styles from './ExpandableContent.module.css'

export type ExpandableContentProps = {
  expandedContent: ReactNode
  collapsedContent: ReactNode
}

export function ExpandableContent({expandedContent, collapsedContent}: ExpandableContentProps) {
  const [isExpanded, setIsExpanded] = useState<boolean>(false)

  return (
    <div className="border border-muted rounded-1">
      {isExpanded ? (
        <>
          <div className={styles.container}>{expandedContent}</div>
          <Link className={styles.link} onClick={() => setIsExpanded(false)}>
            <span>Show less</span> <ChevronUpIcon />
          </Link>
        </>
      ) : (
        <>
          <div className={styles.container}>{collapsedContent}</div>
          <Link className={styles.link} onClick={() => setIsExpanded(true)}>
            <span className="pr-1">Show more</span> <ChevronDownIcon />
          </Link>
        </>
      )}
    </div>
  )
}
