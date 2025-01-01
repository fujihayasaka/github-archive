import {Stack} from '@primer/react'
import type {ReactNode} from 'react'

import styles from './Header.module.css'

type HeaderProps = {
  children?: ReactNode
}

export default function Header({children}: HeaderProps) {
  return (
    <Stack justify={'space-between'} direction={'horizontal'} className={styles.container}>
      {children}
    </Stack>
  )
}
