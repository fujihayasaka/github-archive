import {Text, type SxProp} from '@primer/react'
import {useContext, useEffect} from 'react'
import {getNodeText} from '../shared'
import ChartCardContext from './context'

export type DescriptionProps = {
  children: React.ReactNode
} & SxProp

export function Description({sx, children}: DescriptionProps) {
  const {setDescription, size} = useContext(ChartCardContext)
  useEffect(() => {
    setDescription(getNodeText(children))
  }, [setDescription, children])
  return size !== 'sparkline' ? (
    <Text sx={{color: 'fg.muted', font: 'var(--text-caption-shorthand)', ...sx}}>{children}</Text>
  ) : null
}
Description.displayName = 'ChartCard.Description'
