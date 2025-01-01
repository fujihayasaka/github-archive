import {Box} from '@primer/react'

import {trStyle, borderTop} from './style'

import BillingJobTableCell from './BillingJobTableCell'

import type {BillingJobTableCellData} from './BillingJobTableCell'

interface Props {
  data: BillingJobTableCellData[]
  style?: {[key: string]: string | number | undefined}
}

export type BillingJobTableRowData = BillingJobTableCellData[]

export default function BillingJobTableRow({data, style}: Props) {
  // Default style
  if (!style) style = {...trStyle, ...borderTop}

  return (
    <Box sx={style}>
      {data.map((cell, index) => {
        if (typeof cell === 'string') {
          // eslint-disable-next-line @eslint-react/no-array-index-key
          return <BillingJobTableCell text={cell} key={index} />
        } else {
          // eslint-disable-next-line @eslint-react/no-array-index-key
          return <BillingJobTableCell text={cell.text} style={cell.style} onClick={cell.onClick} key={index} />
        }
      })}
    </Box>
  )
}
