import {Heading, type HeadingProps} from '@primer/react'
import styles from './ScreenReaderHeading.module.css'

export interface ScreenReaderHeadingProps extends Pick<HeadingProps, 'id'> {
  as: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6'
  text: string
}

export function ScreenReaderHeading({as, text, ...props}: ScreenReaderHeadingProps) {
  return (
    <Heading as={as} className={`sr-only ${styles.userSelectNone}`} data-testid="screen-reader-heading" {...props}>
      {text}
    </Heading>
  )
}
