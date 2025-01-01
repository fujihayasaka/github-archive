import type {SafeHTMLString} from '@github-ui/safe-html'
import {SafeHTMLText} from '@github-ui/safe-html'
import {UnsafeHTMLText} from '@github-ui/safe-html/UnsafeHTML'
import {testIdProps} from '@github-ui/test-id-props'
import type {Text} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {
  type AnchorHTMLAttributes,
  type PropsWithChildren,
  type ReactElement,
  type RefObject,
  useEffect,
  useRef,
} from 'react'

import {useNextHeaderTag} from '../hooks/use-next-header-tag'
import {useListViewVariant} from '../ListView/VariantContext'
import type {PrefixedStylableProps} from '../types'
import type {ListItemLeadingBadge} from './LeadingBadge'
import {ListItemSelection} from './Selection'
import styles from './Title.module.css'
import {useListItemTitle} from './TitleContext'
import type {ListItemTrailingBadge} from './TrailingBadge'

export type InternalTitleProps = {
  /**
   * Additional elements to be rendered after the title header element and trailing badge.
   */
  children?: React.ReactNode
  /**
   * A ref object to access the container element of the header.
   */
  headerContainerRef?: React.RefObject<HTMLDivElement>
  /**
   * A ref object to access the container element of the header.
   */
  headingRef?: React.RefObject<HTMLDivElement>
  /*
   * An optional element used to indicate information such as the status of the item. Appears before the title text.
   */
  leadingBadge?: ReactElement<typeof ListItemLeadingBadge>
  /**
   * An optional element used to indicate information such as the status of the item. Appears after the title text.
   */
  trailingBadges?: Array<ReactElement<typeof ListItemTrailingBadge>>
} & PrefixedStylableProps<'container'> &
  PrefixedStylableProps<'heading'>

function InternalTitle({
  children,
  containerStyle,
  containerClassName,
  headerContainerRef: containerRef,
  headingStyle,
  headingClassName,
  headingRef: forwardedHeadingRef,
  leadingBadge,
  trailingBadges,
  header,
}: InternalTitleProps & {header: ReactElement}) {
  const {variant} = useListViewVariant()
  const {setTitle} = useListItemTitle()

  const fallbackHeadingRef = useRef<HTMLDivElement>(null)
  const headingRef = forwardedHeadingRef || fallbackHeadingRef
  const TitleTag = useNextHeaderTag('listitem')

  useEffect(() => {
    if (headingRef?.current?.textContent) {
      setTitle(headingRef.current.textContent.trim())
    }
  }, [headingRef, setTitle])

  return (
    <>
      <div
        {...testIdProps('list-view-item-title-container')}
        style={containerStyle}
        className={clsx(styles.container, variant === 'compact' && styles.compact, containerClassName)}
        ref={containerRef}
      >
        <TitleTag
          className={clsx(styles.heading, variant === 'compact' && styles.compact, headingClassName)}
          style={headingStyle}
          ref={headingRef}
          {...testIdProps('list-view-item-title')}
        >
          {leadingBadge}
          {header}
        </TitleTag>
        {/* Can't use margin because the trailing badges need to wrap inline around the title
        so we add gap after text for spacing */}
        {trailingBadges && <span className={styles.trailingBadgesSpacer} />}
        <span className={styles.trailingBadgesContainer}>{trailingBadges}</span>
        {children}
      </div>
      <ListItemSelection />
    </>
  )
}

export type ListItemTitleProps = InternalTitleProps &
  HeadingLinkProps & {
    /**
     * The text content of the header, to convey the primary meaning of the list item.
     */
    value: string
  }

export function ListItemTitle({
  children,
  value,
  containerStyle,
  containerClassName,
  headerContainerRef,
  headingStyle,
  headingClassName,
  headingRef,
  leadingBadge,
  trailingBadges,
  ...headingLinkProps
}: ListItemTitleProps) {
  return (
    <InternalTitle
      header={
        headingLinkProps.href || headingLinkProps.onClick ? (
          <HeadingLink {...headingLinkProps}>
            <span>{value}</span>
          </HeadingLink>
        ) : (
          <span>{value}</span>
        )
      }
      containerStyle={containerStyle}
      containerClassName={containerClassName}
      headerContainerRef={headerContainerRef}
      headingStyle={headingStyle}
      headingClassName={headingClassName}
      headingRef={headingRef}
      leadingBadge={leadingBadge}
      trailingBadges={trailingBadges}
    >
      {children}
    </InternalTitle>
  )
}

export function ListItemSafeHTMLTitle({
  children,
  html,
  containerStyle,
  containerClassName,
  headerContainerRef,
  headingStyle,
  headingClassName,
  headingRef,
  leadingBadge,
  trailingBadges,
  ...headerProps
}: InternalTitleProps & {
  /**
   * The text content of the header, to convey the primary meaning of the list item.
   */
  html: string
  /**
   * A click handler to be executed when the element is clicked
   */
  onClick?: React.MouseEventHandler<HTMLElement>
}) {
  return (
    <InternalTitle
      header={<UnsafeHTMLText html={html} {...headerProps} />}
      containerStyle={containerStyle}
      containerClassName={containerClassName}
      headerContainerRef={headerContainerRef}
      headingStyle={headingStyle}
      headingClassName={headingClassName}
      headingRef={headingRef}
      leadingBadge={leadingBadge}
      trailingBadges={trailingBadges}
    >
      {children}
    </InternalTitle>
  )
}

/**
 * @warning **CAUTION:** This component is not safe and the HTML must be sanitized before being passed to this component.
 * This component should only be used if the html comes from a trusted source on the server, has
 * known static contents, or has been sanitized by DOMPurify.
 * If not, we recommend using `ListItemSafeHTMLTitle` or ListItemTitle`
 **/
export function ListItemUnsafeHTMLTitle({
  children,
  html,
  containerStyle,
  containerClassName,
  headerContainerRef,
  headingStyle,
  headingClassName,
  headingRef,
  leadingBadge,
  trailingBadges,
  ...headerProps
}: InternalTitleProps & {
  /**
   * **CAUTION:** This prop is not safe. The HTML must be sanitized before being passed to this component.
   * Only supports strings that have specifically been marked as verified,
   * which means either they come from a trusted source on the server, they have
   * known static contents, or they have been sanitized by DOMPurify.
   **/
  html: SafeHTMLString
  /**
   * A click handler to be executed when the element is clicked
   */
  onClick?: React.MouseEventHandler<HTMLElement>
}) {
  return (
    <InternalTitle
      header={<SafeHTMLText html={html} {...headerProps} />}
      containerStyle={containerStyle}
      containerClassName={containerClassName}
      headerContainerRef={headerContainerRef}
      headingStyle={headingStyle}
      headingClassName={headingClassName}
      headingRef={headingRef}
      leadingBadge={leadingBadge}
      trailingBadges={trailingBadges}
    >
      {children}
    </InternalTitle>
  )
}

type HeadingLinkProps = AnchorHTMLAttributes<HTMLAnchorElement> &
  PrefixedStylableProps<'anchor'> & {
    /**
     * A ref to the anchor element
     */
    anchorRef?: RefObject<HTMLAnchorElement>
    /**
     * An optional prop to pass additional props for the anchor tag of the title, if the title is a link
     * Can be used to add a target or soft navigation, for example
     */
    linkProps?: Omit<React.ComponentPropsWithoutRef<typeof Text>, 'sx'>
  }

function HeadingLink({
  anchorStyle,
  anchorClassName,
  anchorRef: forwardedAnchorRef,
  linkProps,
  children,
  ...componentProps
}: PropsWithChildren<HeadingLinkProps>) {
  const {setTitleAction} = useListItemTitle()
  const {as: As = 'a', ...restLinkProps} = linkProps ?? {}
  const fallbackAnchorRef = useRef<HTMLAnchorElement>(null)
  const anchorRef = forwardedAnchorRef || fallbackAnchorRef

  useEffect(() => {
    if (componentProps.href || componentProps.onClick) {
      setTitleAction(() => (e: KeyboardEvent) => {
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        if (componentProps.href && (e.metaKey || e.ctrlKey)) {
          // open the link in a new tab when command or control are pressed
          window.open(componentProps.href, '_blank')
        } else {
          anchorRef?.current?.click()
        }
      })
    }
  }, [anchorRef, componentProps.href, componentProps.onClick, setTitleAction])

  return (
    <As
      {...testIdProps('listitem-title-link')}
      style={anchorStyle}
      ref={anchorRef}
      className={clsx(styles.anchor, styles.inline, anchorClassName)}
      {...componentProps}
      {...restLinkProps}
    >
      {children}
    </As>
  )
}
