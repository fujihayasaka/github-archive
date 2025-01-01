import {clsx} from 'clsx'
import {createElement, type HTMLAttributes, type ReactNode} from 'react'

import {useLabelId} from '../LabelIdContext'
import styles from './Title.module.css'

type HeadingTag = 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6'

type HeaderTitleProps = {
  children?: ReactNode
  headingLevel: HeadingTag
} & HTMLAttributes<HTMLHeadingElement>

export default function Title({headingLevel, children, className, ...props}: HeaderTitleProps) {
  const id = useLabelId()

  return (
    <HeadingTag id={id} headingLevel={headingLevel} className={clsx(styles.title, className)} {...props}>
      {children}
    </HeadingTag>
  )
}

// Use own Heading component instead of Primer to avoid CSS specificity issues with Primer's CSS Modules style
function HeadingTag({headingLevel, children, ...props}: HeaderTitleProps) {
  const Tag = `${headingLevel}` as keyof JSX.IntrinsicElements
  return createElement(Tag, props, children)
}
