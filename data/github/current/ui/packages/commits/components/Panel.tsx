import {clsx} from 'clsx'
import type {PropsWithChildren} from 'react'

interface PanelProps {
  className?: string
}

export function Panel({children, className = ''}: PropsWithChildren<PanelProps>) {
  return (
    <div
      className={clsx(
        'color-bg-default position-relative border rounded-2 color-border-default mt-2 d-flex flex-column',
        className,
      )}
    >
      {children}
    </div>
  )
}
