import {CheckIcon, StopIcon} from '@primer/octicons-react'
import {Animate, AnimationProvider, Stack} from '@primer/react-brand'
import {clsx} from 'clsx'
import type React from 'react'

import styles from './Flash.module.css'

function FlashWrapper(props: {children?: React.ReactNode}) {
  return (
    <div role="alert" aria-atomic>
      {props.children}
    </div>
  )
}

export type FlashProps = {
  children: React.ReactNode
  hidden?: boolean
  variant: 'success' | 'error'
}

export function Flash({children, hidden, variant}: FlashProps) {
  if (hidden) {
    /**
     * If the Flash is hidden, we should still render the FlashWrapper to ensure updates to this
     * component are properly announced to screen readers
     */
    return <FlashWrapper />
  }

  return (
    <FlashWrapper>
      <AnimationProvider runOnce>
        <Animate animate="fade-in">
          <Stack
            className={clsx(styles.Flash, variant === 'error' ? styles.FlashError : styles.FlashSuccess)}
            direction="horizontal"
            justifyContent="flex-start"
            gap={16}
          >
            <div className={variant === 'success' ? styles.FlashIconSuccess : styles.FlashIconError}>
              {variant === 'success' ? <CheckIcon size={16} /> : <StopIcon size={16} />}
            </div>

            <div>{children}</div>
          </Stack>
        </Animate>
      </AnimationProvider>
    </FlashWrapper>
  )
}
