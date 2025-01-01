import {clsx} from 'clsx'
import type {PropsWithChildren} from 'react'

export interface LinesChangedCounterLabelProps {
  isAddition?: boolean
  className?: string
}

export function LinesChangedCounterLabel({
  children,
  isAddition,
  className,
}: PropsWithChildren<LinesChangedCounterLabelProps>) {
  return (
    <div className={clsx('ml-1 text-small text-bold', isAddition ? 'fgColor-success' : 'fgColor-danger', className)}>
      {children}
    </div>
  )
}
