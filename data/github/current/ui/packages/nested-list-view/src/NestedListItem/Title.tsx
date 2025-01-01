import {type SafeHTMLString, SafeHTMLText} from '@github-ui/safe-html'
import {testIdProps} from '@github-ui/test-id-props'
import {Link, type Text} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {type ForwardedRef, type PropsWithChildren, type ReactElement, useEffect, useRef} from 'react'

import {useNestedListItemControlsDialog} from './context/ControlsDialogContext'
import {useNestedListItemTitle} from './context/TitleContext'
import type {NestedListItemLeadingBadge} from './LeadingBadge'
import styles from './Title.module.css'
import type {NestedListItemTrailingBadge} from './TrailingBadge'

export type NestedListItemTitleProps = PropsWithChildren<{
  containerClassName?: string

  /*
   * An optional element used to indicate information such as the status of the item. Appears before the title text.
   */
  leadingBadge?: ReactElement<typeof NestedListItemLeadingBadge>

  /*
   * An optional element used to indicate information such as the status of the item. Appears after the title text.
   */
  trailingBadges?: Array<ReactElement<typeof NestedListItemTrailingBadge>>
}> &
  NestedListItemHeadingLinkProps

type NestedListItemHeadingLinkProps = {
  anchorClassName?: string
  /**
   * A ref to the anchor element
   */
  anchorRef?: ForwardedRef<HTMLAnchorElement>
  /**
   * The link that will be opened when the item is clicked
   */
  href?: string
  /*
   * An optional prop to pass additional props for the anchor tag of the title, if the title is a link
   * Can be used to add a target or soft navigation, for example
   */
  additionalLinkProps?: React.ComponentPropsWithoutRef<typeof Text>
  /**
   * A click handler to be executed when the element is clicked
   */
  onClick?: React.MouseEventHandler<HTMLElement>
  /**
   * The tooltip to add context to the title
   */
  tooltip?: string
  /**
   * The text content of the header, to convey the primary meaning of the list item.
   */
  value: SafeHTMLString | string
}

export function NestedListItemTitle({
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  additionalLinkProps = {} as React.ComponentPropsWithoutRef<typeof Text>,
  anchorRef: forwardedAnchorRef,
  anchorClassName,
  children,
  containerClassName,
  href,
  leadingBadge,
  onClick,
  tooltip,
  trailingBadges,
  value,
}: NestedListItemTitleProps) {
  const {setTitle, setTitleAction} = useNestedListItemTitle()
  const {controlsDialogOpen} = useNestedListItemControlsDialog()
  const fallbackAnchorRef = useRef<HTMLAnchorElement>(null)
  const anchorRef = forwardedAnchorRef || fallbackAnchorRef

  // Set title for NestedListItem aria-label property
  useEffect(() => {
    const ariaLabelTitle = (typeof anchorRef !== 'function' && anchorRef?.current?.textContent) || value
    setTitle(ariaLabelTitle)
  }, [anchorRef, setTitle, value])
  useEffect(() => {
    if ((href || onClick) && typeof anchorRef !== 'function' && anchorRef?.current) {
      setTitleAction(() => (e: KeyboardEvent) => {
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        if (href && (e.metaKey || e.ctrlKey)) {
          // open the link in a new tab when command or control are pressed
          window.open(href, '_blank')
        } else {
          anchorRef?.current?.click()
        }
      })
    }
  }, [anchorRef, href, onClick, setTitleAction])

  return (
    <div
      {...testIdProps('nested-list-view-item-primary-container')}
      className={clsx(styles.container, containerClassName)}
    >
      {leadingBadge}
      <Link
        // Intentionally setting the role to presentation to prevent the link from being announced by screen readers when the management dialog is not open
        // More information: https://ui.githubapp.com/storybook/?path=/docs/recipes-nested-list-view-documentation-accessibility-listitem--docs#titleprimary-action-example-markup
        {...(!controlsDialogOpen ? {role: 'none'} : {})}
        ref={anchorRef}
        className={clsx(styles.anchor, styles.truncate, anchorClassName)}
        href={href}
        onClick={onClick}
        {...additionalLinkProps}
        {...testIdProps('listitem-title-link')}
      >
        <SafeHTMLText html={value as SafeHTMLString} title={tooltip} />
      </Link>
      {/* Can't use margin because the trailing badges need to wrap inline around the title
        so we add gap after text for spacing */}
      {trailingBadges && <span className={clsx(styles.trailingBadges, styles.truncate)}>{trailingBadges}</span>}
      {children}
    </div>
  )
}
