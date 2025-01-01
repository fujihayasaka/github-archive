import type React from 'react'
import {Label} from '@primer/react'

const RowLabel: React.FC<{text: string}> = ({text}) => {
  return <Label variant="secondary">{text}</Label>
}

export default RowLabel
