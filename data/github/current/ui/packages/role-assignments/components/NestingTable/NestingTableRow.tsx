import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {Text, IconButton, Label} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {useState, useRef, useEffect, useId, type ReactElement} from 'react'
import styles from './NestingTableRow.module.css'
import {testIdProps} from '@github-ui/test-id-props'

interface NestingTableRowProps {
  leadingIcon: React.ReactNode
  title: string
  titleLabel?: string
  description?: React.ReactNode
  trailingItems?: React.ReactNode[]
  subItems?: Array<ReactElement<typeof NestingTableRow>>
}

export function NestingTableRow({
  leadingIcon,
  title,
  titleLabel,
  description,
  trailingItems,
  subItems,
}: NestingTableRowProps) {
  const hasSubItems = (subItems?.length || 0) > 0
  const hasTrailingItems = (trailingItems?.length || 0) > 0

  const subListId = useId()
  const [isExpanded, setIsExpanded] = useState(false)

  // We need to measure the last subitem's height when expanded to set the height of the hierarchy line
  const [lastSubitemHeight, setLastSubitemHeight] = useState(90)
  const subItemsContainerRef = useRef<HTMLUListElement>(null)

  // When expanded, measure the last subitem's height and set the CSS var
  useEffect(() => {
    if (isExpanded && subItemsContainerRef.current) {
      const children = subItemsContainerRef.current.children
      if (children.length > 0) {
        const lastChild = children[children.length - 1] as HTMLElement
        setLastSubitemHeight(lastChild.offsetHeight)
      }
    }
  }, [isExpanded, subItems])

  return (
    <li
      className={clsx(styles.row, {[styles.noSubitems]: !hasSubItems, [styles.rowExpanded]: isExpanded})}
      // When expanded, set the CSS variable --last-subitem-height dynamically
      style={isExpanded ? ({'--last-subitem-height': `${lastSubitemHeight}px`} as React.CSSProperties) : {}}
    >
      <div className="d-flex">
        <div className={styles.leadingItems}>
          {hasSubItems && (
            <span className={styles.toggleButtonContainer} {...testIdProps('sublist-toggle')}>
              {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
              <IconButton
                icon={isExpanded ? ChevronDownIcon : ChevronRightIcon}
                variant="invisible"
                unsafeDisableTooltip
                aria-controls={subListId}
                aria-expanded={isExpanded}
                aria-label={isExpanded ? `Collapse ${title}` : `Expand ${title}`}
                size="small"
                onClick={() => setIsExpanded(!isExpanded)}
                className={styles.toggleButton}
              />
            </span>
          )}
          <span className={styles.leadingIcon}>{leadingIcon}</span>
        </div>
        <div className={styles.content}>
          <span className={styles.mainContent}>
            <div className="d-flex gap-2">
              <Text weight="semibold">{title}</Text>
              {titleLabel && <Label {...testIdProps('title-label')}>{titleLabel}</Label>}
            </div>
            {description != null && description !== '' && (
              <span className="fgColor-muted" {...testIdProps('description')}>
                {description}
              </span>
            )}
          </span>
          {hasTrailingItems && <span className={styles.trailingItems}>{trailingItems}</span>}
        </div>
      </div>

      {hasSubItems && isExpanded && (
        <ul id={subListId} ref={subItemsContainerRef} className={styles.children} {...testIdProps('sublist')}>
          {subItems}
        </ul>
      )}
    </li>
  )
}
