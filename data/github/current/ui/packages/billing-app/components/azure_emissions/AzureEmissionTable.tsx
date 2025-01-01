import type {AzureEmission} from '../../types/azure-emissions'
import {formatMoneyDisplay} from '../../utils/money'
import {DataTable, Table} from '@primer/react/experimental'

import {BriefcaseIcon, GlobeIcon} from '@primer/octicons-react'

interface AzureEmissionTableProps {
  azureEmissions: AzureEmission[]
}

export default function AzureEmissionTable({azureEmissions}: AzureEmissionTableProps) {
  return (
    <Table.Container data-testid="azure-emission-table">
      <DataTable
        aria-labelledby="azure-emissions"
        aria-describedby="azure-emissions-subtitle"
        data-testid="azure-emission-table"
        data={azureEmissions}
        columns={[
          {
            header: 'Billed Entity',
            field: 'usageEntity',
            renderCell: row => {
              if (row.usageEntity.isCostCenter) {
                return (
                  <span className="gap-1">
                    <BriefcaseIcon size={16} className="mr-1" />
                    {row.usageEntity.name}
                  </span>
                )
              } else {
                return (
                  <span className="gap-1">
                    <GlobeIcon size={16} className="mr-1" />
                    {'Parent Entity'}
                  </span>
                )
              }
            },
          },
          {
            header: 'Azure Subscription Id',
            field: 'subscriptionId',
          },
          {
            header: 'SKU',
            field: 'friendlySkuName',
          },
          {
            header: 'Emission Status',
            field: 'status',
            renderCell: row => {
              return row.status
            },
          },
          {
            header: 'Quantity',
            field: 'quantity',
            renderCell: row => {
              return Math.round(row.quantity * 1000) / 1000 // Round to 3 decimal places if necessary
            },
          },
          {
            header: 'Estimated Billed Amount',
            field: 'estimatedBilledAmount',
            renderCell: row => {
              return formatMoneyDisplay(row.estimatedBilledAmount)
            },
          },
        ]}
      />
    </Table.Container>
  )
}
