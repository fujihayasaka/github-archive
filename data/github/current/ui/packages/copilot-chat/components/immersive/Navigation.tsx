import {Link} from '@github-ui/react-core/link'
import {ChevronDownIcon, ChevronRightIcon, type Icon, KebabHorizontalIcon} from '@primer/octicons-react'
import {type ComponentProps, type MouseEvent, type ReactNode, useState} from 'react'
import type {LinkProps} from 'react-router-dom'

import styles from './Navigation.module.css'

type NavigationPropsBase = {
  children?: ReactNode
  /**
   * Context menu component that is rendered right-aligned in the link.
   */
  contextMenuComponent?: ReactNode
  /**
   * Expand the navigation's sub items when the link is clicked.
   */
  expandOnClick?: boolean
  /**
   * Indicates that the link has sub-items.
   */
  hasItems?: boolean
  /**
   * The URL to navigate to when the link is clicked.
   */
  href: string
  /**
   * The icon to display next to the link text.
   */
  icon?: Icon
  /**
   * Icon override to render custom react.
   */
  iconOverride?: ReactNode
  /**
   * A callback that is called when the link is clicked.
   */
  onLinkClick?: (e: MouseEvent<HTMLAnchorElement>, page: string) => void
  /**
   * The ID of the navigation item.
   */
  id: string
  /**
   * The display name of the navigation item.
   */
  displayName: string
  label?: ReactNode
} & Pick<LinkProps, 'aria-current'>

type NavigationPropsWithIcon = NavigationPropsBase & {
  icon: Icon
  iconOverride?: never
}

type NavigationPropsWithIconOverride = NavigationPropsBase & {
  icon?: never
  iconOverride: ReactNode
}

type NavigationProps = NavigationPropsWithIcon | NavigationPropsWithIconOverride

export function Navigation({
  'aria-current': ariaCurrent,
  children,
  contextMenuComponent,
  expandOnClick = true,
  hasItems,
  href,
  icon: Icon,
  iconOverride,
  onLinkClick,
  id,
  displayName,
  label,
}: NavigationProps) {
  const [expanded, setExpanded] = useState(false)

  const toggleExpand = () => {
    setExpanded(!expanded)
  }

  const handleLinkClick = (e: MouseEvent<HTMLAnchorElement>) => {
    onLinkClick?.(e, id)
    if (expandOnClick) setExpanded(true)
  }

  const commonLinkProps = {
    'aria-current': ariaCurrent,
    className: styles.link,
    onClick: handleLinkClick,
  }

  return (
    <li className={styles.section}>
      <div className={styles.item}>
        {hasItems && (
          <button aria-label="Expand" aria-expanded={expanded} className={styles.expandButton} onClick={toggleExpand}>
            {expanded ? <ChevronDownIcon size={12} /> : <ChevronRightIcon size={12} />}
          </button>
        )}
        <Link to={href} {...commonLinkProps}>
          <div className={styles.icon}>{Icon ? <Icon size={16} /> : iconOverride}</div>
          <div className={styles.textWrapper}>
            <div className={styles.text}>{displayName}</div>
          </div>
          {label}
        </Link>
        {contextMenuComponent}
      </div>
      {expanded && hasItems && <ul className={styles.subList}>{children}</ul>}
    </li>
  )
}

type NavigationSubItemPropsBase = {
  /**
   * Context menu component that is rendered right-aligned in the link.
   */
  contextMenuComponent?: ReactNode
  /**
   * Display name of the link.
   */
  displayName: string
  /**
   * The URL to navigate to when the link is clicked.
   */
  href: string
  /**
   * The icon to display next to the link text.
   */
  icon?: Icon
  /**
   * An override for the icon prop to render custom react.
   */
  iconOverride?: ReactNode
  /**
   * A callback that is called when the link is clicked.
   */
  onLinkClick: (e: MouseEvent<HTMLAnchorElement>) => void
} & Pick<LinkProps, 'aria-current'>

type NavigationSubItemPropsWithIcon = NavigationSubItemPropsBase & {
  icon: Icon
  iconOverride?: never
}

type NavigationSubItemPropsWithIconOverride = NavigationSubItemPropsBase & {
  icon?: never
  iconOverride: ReactNode
}

type NavigationSubItemProps = NavigationSubItemPropsWithIcon | NavigationSubItemPropsWithIconOverride

export function NavigationSubItem({
  'aria-current': ariaCurrent,
  contextMenuComponent,
  displayName,
  href,
  icon: Icon,
  iconOverride,
  onLinkClick,
}: NavigationSubItemProps) {
  return (
    <li className={styles.item}>
      <Link className={styles.link} to={href} aria-current={ariaCurrent} onClick={onLinkClick}>
        {Icon ? <Icon size={16} className={styles.icon} /> : iconOverride}
        <div className={styles.textWrapper}>
          <div className={styles.text}>{displayName}</div>
        </div>
      </Link>
      {contextMenuComponent}
    </li>
  )
}

export function NavigationContextMenuButton(props: ComponentProps<'button'>) {
  return (
    <button {...props} className={styles.contextButton}>
      <KebabHorizontalIcon size={16} />
    </button>
  )
}
