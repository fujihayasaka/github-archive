import {useContext} from 'react'
import ChartCardContext from './context'

export interface LeadingVisualProps {
  children: React.ReactNode
}

const LeadingVisual = ({children}: LeadingVisualProps) => {
  const {size} = useContext(ChartCardContext)
  return size !== 'sparkline' ? <>{children}</> : null
}

export default LeadingVisual
