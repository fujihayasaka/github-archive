import {Link} from '@primer/react'
import {clsx} from 'clsx'

import {useLabelId} from '../LabelIdContext'
import styles from './Title.module.css'

type StaticTitleProps = {
  children: React.ReactNode
}

type LinkTitleProps = StaticTitleProps & {
  /** Optional URL to navigate to on click. */
  href: string
}

type ActionTitleProps = StaticTitleProps & {
  /**
   * Optional click handler to open a dialog or side panel on click. Note that this MUST NOT navigate the page: use
   * `href` instead.
   */
  onClick: React.MouseEventHandler
}

type TitleProps = LinkTitleProps | ActionTitleProps | StaticTitleProps

export default function Title({children, ...props}: TitleProps) {
  const id = useLabelId()
  const commonProps = {className: styles.title, id, children}
  const interactiveProps = {...commonProps, inline: true, className: clsx(styles.title, styles.link)}

  return 'href' in props ? (
    <Link href={props.href} {...interactiveProps} />
  ) : 'onClick' in props ? (
    <Link as="button" onClick={props.onClick} {...interactiveProps} />
  ) : (
    <span {...commonProps} />
  )
}
