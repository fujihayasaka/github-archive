import DataCard from '@github-ui/data-card'
import {AlertIcon, ShieldCheckIcon} from '@primer/octicons-react'
import {Label, sx} from '@primer/react'
import {Blankslate, DataTable, Table} from '@primer/react/experimental'
import {useMemo} from 'react'

import SeverityLabel from '../../../common/components/severity-label'
import type {SastData, UseSastQueryParams} from './use-sast-query'
import useSastQuery from './use-sast-query'

interface SastTableProps extends UseSastQueryParams {}

interface TableRow extends SastData {
  id: number
}

const numberFormatter = Intl.NumberFormat('en-US', {notation: 'standard'})

export function SastTable(props: SastTableProps): JSX.Element {
  const dataQuery = useSastQuery(props)
  const rows = (): TableRow[] => {
    if (dataQuery.isSuccess) {
      return dataQuery.data.data.map<TableRow>((item, idx) => {
        return {...item, id: idx}
      })
    } else {
      return []
    }
  }

  const blankslateParentStyle = useMemo(() => {
    return {display: 'flex', flexDirection: 'column', height: 366, width: '100%', justifyContent: 'center'}
  }, [])

  if (dataQuery.isPending) {
    return (
      <Table.Container sx={{my: 4}}>
        <Table.Skeleton
          columns={[
            {header: 'Type'},
            {header: 'Common Weakness Enumerator'},
            {header: 'Open alerts'},
            {header: 'Severity'},
          ]}
          rows={10}
        />
      </Table.Container>
    )
  }

  if (dataQuery.isError) {
    return (
      <DataCard sx={blankslateParentStyle} data-testid="error">
        <Blankslate>
          <Blankslate.Visual>
            <AlertIcon size="medium" />
          </Blankslate.Visual>
          <Blankslate.Description>Information could not be loaded right now</Blankslate.Description>
        </Blankslate>
      </DataCard>
    )
  }

  if (dataQuery.isSuccess && dataQuery.data.data.length === 0) {
    return (
      <DataCard sx={blankslateParentStyle} data-testid="empty">
        <Blankslate>
          <Blankslate.Visual>
            <ShieldCheckIcon size="medium" />
          </Blankslate.Visual>
          <Blankslate.Description>
            Try modifying your filters to see the security impact on your organization.
          </Blankslate.Description>
        </Blankslate>
      </DataCard>
    )
  }

  return (
    <Table.Container sx={{my: 4, ...sx}}>
      <DataTable
        data={rows()}
        columns={[
          {
            header: 'Type',
            field: 'name',
            renderCell: (data: TableRow) => (
              <div>
                <div className="h5">{data.name}</div>
                <div className="fgColor-muted">{data.ruleSarifId}</div>
              </div>
            ),
          },
          {
            header: 'Common Weakness Enumerator',
            field: 'cwes',
            renderCell: (data: TableRow) =>
              data.cwes.map((cwe, idx) => (
                // eslint-disable-next-line @eslint-react/no-array-index-key
                <Label key={idx} variant="secondary">
                  {cwe}
                </Label>
              )),
          },
          {
            header: 'Open alerts',
            field: 'countOpenAlerts',
            align: 'end',
            renderCell: (data: TableRow) => numberFormatter.format(data.countOpenAlerts),
          },
          {
            header: 'Severity',
            field: 'severity',
            renderCell: (data: TableRow) => <SeverityLabel severity={data.severity} />,
          },
        ]}
      />
    </Table.Container>
  )
}
