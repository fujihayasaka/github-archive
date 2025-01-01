import type {SxProp} from '@primer/react'
import {Text} from '@primer/react'
import type {PropsWithChildren} from 'react'

const defaultStyle = {
  font: 'var(--text-caption-shorthand)',
  marginTop: 2,
  color: 'fg.muted',
}

export interface DescriptionProps extends SxProp {}

export function Description({sx, children}: PropsWithChildren<DescriptionProps>) {
  const style = {...defaultStyle, sx}

  return (
    <Text as="p" sx={style}>
      {children}
    </Text>
  )
}
