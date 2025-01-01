import {useContext} from 'react'
import ChartCardContext from './context'

export interface TrailingVisualProps {
  children: React.ReactNode
}

const TrailingVisual = ({children}: TrailingVisualProps) => {
  const {size} = useContext(ChartCardContext)
  return size !== 'sparkline' ? <>{children}</> : null
}

export default TrailingVisual
