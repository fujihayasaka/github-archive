import {Box, Text} from '@primer/react-brand'
import {CheckIcon, DashIcon} from '@primer/octicons-react'
import type {CellDetails} from './PricingData'

interface PricingTableCellProps {
  planName: string
  value: boolean | CellDetails
}

export default function PricingTableCell({value, planName}: PricingTableCellProps) {
  return (
    <Box
      role="cell"
      className={`col-12 col-lg-4 lp-Pricing-table-cell text-center ${
        value ? 'lp-Pricing-included' : 'lp-Pricing-not-included'
      }`}
    >
      <Text size="100" className="lp-Pricing-table-cell-plan d-md-none mr-auto">
        {planName} <span className="sr-only">plan</span>
      </Text>
      {typeof value === 'object' ? (
        <>
          <Text size="100" className="d-md-none">
            {value.text}
          </Text>
          {value.icon}
          <Text size="100" className="d-none d-md-block">
            {value.text}
          </Text>
        </>
      ) : (
        <>
          {value ? <CheckIcon /> : <DashIcon />}
          {value ? <span className="sr-only">Included</span> : <span className="sr-only">Not included</span>}
        </>
      )}
    </Box>
  )
}
