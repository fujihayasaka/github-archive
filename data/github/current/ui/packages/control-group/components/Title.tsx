import type {SxProp} from '@primer/react'
import {Heading} from '@primer/react'

import styles from './Title.module.css'
import {clsx} from 'clsx'

export type TitleProps = React.HTMLAttributes<HTMLElement> & {
  children: React.ReactNode | string
  as?: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6'
  sx?: SxProp
  className?: string
}

const Title = ({children, as = 'h3', sx, className, ...restProps}: TitleProps) => {
  return (
    <Heading {...restProps} as={as} sx={{...sx}} className={clsx(styles.Heading, className)}>
      {children}
    </Heading>
  )
}
Title.displayName = 'ControlGroup.Title'

export default Title
