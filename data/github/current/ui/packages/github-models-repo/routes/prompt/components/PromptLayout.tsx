import {clsx} from 'clsx'
import type {PropsWithChildren} from 'react'
import styles from './PromptLayout.module.css'
import {Stack} from '@primer/react'

export function PromptLayout({children, fullscreen}: PropsWithChildren & {fullscreen?: boolean}) {
  return (
    <Stack
      className={clsx(styles.wrapper, 'fill-page-height', {
        [styles.wrapperFullscreen]: fullscreen,
      })}
    >
      {children}
    </Stack>
  )
}
