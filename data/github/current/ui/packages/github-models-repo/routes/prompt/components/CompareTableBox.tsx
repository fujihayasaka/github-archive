import {Heading} from '@primer/react'
import {clsx} from 'clsx'
import type {PropsWithChildren, ReactNode} from 'react'
import styles from './CompareTableBox.module.css'

export function CompareTableBox({
  id,
  heading,
  className,
  children,
}: PropsWithChildren<{heading: ReactNode; className?: string; id: string}>) {
  return (
    <div className={clsx('Box rounded-1 overflow-hidden', className)}>
      <div className="Box-header rounded-top-1 p-2">
        <Heading as="h1" className="h6 px-1" variant="small" id={id}>
          {heading}
        </Heading>
      </div>

      <div className={styles.CustomTable}>{children}</div>
    </div>
  )
}
