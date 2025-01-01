import {type SafeHTMLString, SafeHTMLText} from '@github-ui/safe-html'
import {testIdProps} from '@github-ui/test-id-props'
import type {Text} from '@primer/react'
import {clsx} from 'clsx'
import type {ForwardedRef, PropsWithChildren, ReactElement, RefObject} from 'react'

import {useNextHeaderTag} from '../hooks/use-next-header-tag'
import type {PrefixedStylableProps} from '../types'
import type {ListItemLeadingBadge} from './LeadingBadge'
import styles from './TitleHeader.module.css'

type BaseTitleHeaderProps = {
  /**
   * The tooltip to add context to the title
   */
  tooltip?: string
  /*
   * An optional element used to indicate information such as the status of the item. Appears before the title text.
   */
  leadingBadge?: ReactElement<typeof ListItemLeadingBadge>
}

type TitleHeadingProps = PrefixedStylableProps<'heading'> & {
  headingRef?: RefObject<HTMLHeadingElement>
}

function TitleHeading({headingStyle, headingClassName, headingRef, children}: PropsWithChildren<TitleHeadingProps>) {
  const TitleTag = useNextHeaderTag('listitem')
  return (
    <TitleTag className={clsx('markdown-title', headingClassName)} style={headingStyle} ref={headingRef}>
      {children}
    </TitleTag>
  )
}

type HeadingLinkProps = PrefixedStylableProps<'anchor'> & {
  /**
   * A ref to the anchor element
   */
  anchorRef?: ForwardedRef<HTMLAnchorElement>
  /**
   * The link that will be opened when the item is clicked
   */
  href?: string
  /**
   * The target of the link that will be opened when the item is clicked
   */
  target?: string
  /**
   * A click handler to be executed when the element is clicked
   */
  onClick?: React.MouseEventHandler<HTMLElement>
  onMouseEnter?: React.MouseEventHandler<HTMLElement>
  onMouseLeave?: React.MouseEventHandler<HTMLElement>
  /**
   * An optional prop to pass additional props for the anchor tag of the title, if the title is a link
   * Can be used to add a target or soft navigation, for example
   */
  linkProps?: Omit<React.ComponentPropsWithoutRef<typeof Text>, 'sx'>
}

export function HeadingLink({
  anchorStyle,
  anchorClassName,
  linkProps,
  anchorRef,
  children,
  ...args
}: PropsWithChildren<HeadingLinkProps>) {
  const {as: As = 'a', ...restProps} = linkProps ?? {}
  return (
    <As
      {...testIdProps('listitem-title-link')}
      style={anchorStyle}
      ref={anchorRef}
      className={clsx(styles.inline, anchorClassName)}
      {...args}
      {...restProps}
    >
      {children}
    </As>
  )
}

export type ListItemMarkdownHeaderProps = BaseTitleHeaderProps &
  TitleHeadingProps &
  HeadingLinkProps & {
    /**
     * The rendered markdown text content of the header, to convey the primary meaning of the list item.
     * When provided, `value` will be used as the title's `title` attribute and `markdownValue` will be used as the title's text content.
     * If `markdownValue` includes links and a `href` is provided, the `markdownValue` will build accessible links.
     */
    markdownValue: SafeHTMLString
  }

export function ListItemMarkdownHeader({
  markdownValue,
  anchorStyle,
  anchorClassName,
  headingStyle,
  headingClassName,
  headingRef,
  tooltip,
  leadingBadge,
  anchorRef,
  linkProps,
  ...props
}: ListItemMarkdownHeaderProps) {
  return (
    <TitleHeading headingStyle={headingStyle} headingClassName={headingClassName} headingRef={headingRef}>
      {leadingBadge}
      {/* markdownValue will provide a link if necessary */}
      <SafeHTMLText
        style={anchorStyle}
        className={clsx(styles.inline, anchorClassName)}
        html={markdownValue}
        title={tooltip}
        {...props}
      />
    </TitleHeading>
  )
}

export type ListItemLinkHeaderProps = BaseTitleHeaderProps &
  TitleHeadingProps &
  HeadingLinkProps & {
    /**
     * The text content of the header, to convey the primary meaning of the list item.
     */
    value: SafeHTMLString | string
  }

export function ListItemLinkHeader({
  headingStyle,
  headingClassName,
  headingRef,
  value,
  tooltip,
  leadingBadge,
  ...args
}: ListItemLinkHeaderProps) {
  return (
    <TitleHeading headingStyle={headingStyle} headingClassName={headingClassName} headingRef={headingRef}>
      {leadingBadge}
      <HeadingLink {...args}>
        <SafeHTMLText html={value as SafeHTMLString} title={tooltip} />
      </HeadingLink>
    </TitleHeading>
  )
}

export type ListItemStaticHeaderProps = BaseTitleHeaderProps &
  TitleHeadingProps & {
    /**
     * The text content of the header, to convey the primary meaning of the list item.
     */
    value: SafeHTMLString | string
  }

export function ListItemStaticHeader({
  value,
  headingStyle,
  headingClassName,
  headingRef,
  tooltip,
  leadingBadge,
}: ListItemStaticHeaderProps) {
  return (
    <TitleHeading headingStyle={headingStyle} headingClassName={headingClassName} headingRef={headingRef}>
      {leadingBadge}
      <SafeHTMLText className={styles.inline} html={value as SafeHTMLString} title={tooltip} />
    </TitleHeading>
  )
}
