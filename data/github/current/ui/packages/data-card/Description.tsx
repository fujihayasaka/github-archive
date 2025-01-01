import type {SxProp} from '@primer/react'
import {Text} from '@primer/react'
import type {PropsWithChildren} from 'react'
import {clsx} from 'clsx'

import styles from './Description.module.css'

export interface DescriptionProps extends SxProp {
  className?: string
}

export function Description({sx, className, children}: PropsWithChildren<DescriptionProps>) {
  const style = {
    sx,
  }

  return (
    <Text as="p" sx={style} className={clsx(className, styles.Text)}>
      {children}
    </Text>
  )
}
