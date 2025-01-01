import {testIdProps} from '@github-ui/test-id-props'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {Heading, IconButton} from '@primer/react'
import {clsx} from 'clsx'
import {type ReactNode, useEffect, useRef} from 'react'

import {useNestedListViewProperties} from '../context/PropertiesContext'
import {useNextHeaderTag} from '../hooks/use-next-header-tag'
import styles from './Title.module.css'

export type NestedListViewHeaderTitleProps = {
  title: string
  children?: ReactNode
  className?: string
  onSetExpanded?: (isExpanded: boolean) => void
  /**
   * The offset from the top to scroll to after collapsing
   */
  scrollToOnCollapseOffset?: number
}

export const NestedListViewHeaderTitle = ({
  title,
  children,
  className,
  scrollToOnCollapseOffset,
}: NestedListViewHeaderTitleProps) => {
  const titleTag = useNextHeaderTag('nested-list-view-metadata')
  const {isCollapsible, isExpanded, setIsExpanded} = useNestedListViewProperties()
  const containerRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    const {current} = containerRef

    if (scrollToOnCollapseOffset !== undefined && current !== null && !isExpanded) {
      const top = current.getBoundingClientRect().top + window.scrollY + scrollToOnCollapseOffset

      window.scrollTo({top, behavior: 'instant'})
    }
  }, [isExpanded, scrollToOnCollapseOffset])

  return (
    <div ref={containerRef} className={clsx(styles.container, className)}>
      <Heading as={titleTag} className={styles.header} {...testIdProps('nested-list-view-header-title')}>
        {/* Add icon button component to expand or collapse the nested list view depending on the isCollapsible prop */}
        {isCollapsible && (
          <IconButton
            icon={isExpanded ? ChevronDownIcon : ChevronRightIcon}
            onClick={() => {
              setIsExpanded(!isExpanded)
            }}
            aria-label={isExpanded ? `Collapse ${title}` : `Expand ${title}`}
            size="small"
            variant="invisible"
            aria-expanded={isExpanded}
            className={styles.expandButton}
            tooltipDirection="n"
          />
        )}
        {title}
      </Heading>
      {children}
    </div>
  )
}
