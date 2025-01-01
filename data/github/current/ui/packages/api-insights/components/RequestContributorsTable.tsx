import {GitHubAvatar} from '@github-ui/github-avatar'
import {Link} from '@primer/react'
import {DataTable, Table, Blankslate} from '@primer/react/experimental'
import {InstallationAvatar} from '../components/InstallationAvatar'

export interface RequestContributorsTableProps {
  rows: RequestContributorsTableRow[]
}

export interface RequestContributorsTableRow {
  id: string
  name: string
  actor_type: string
  requests: string
  icon_url?: string
  href?: string
  installation_icon?: boolean
  icon_background_color?: string
  square_icon?: boolean
}

export function RequestContributorsTable({rows}: RequestContributorsTableProps) {
  const showBlankslate = rows.length === 0

  return (
    <div className="d-flex flex-column gap-3 mt-3">
      {showBlankslate && (
        <Blankslate>
          <Blankslate.Heading>No contributors found</Blankslate.Heading>
        </Blankslate>
      )}
      {!showBlankslate && (
        <Table.Container>
          <DataTable
            aria-labelledby="actors"
            aria-describedby="actors-subtitle"
            data={rows}
            columns={[
              {
                header: () => {
                  return <span className="f6 fgColor-muted">Name</span>
                },
                field: 'name',
                rowHeader: true,
                renderCell: row => {
                  const installation_icon = row?.installation_icon || false
                  const square_icon = row?.square_icon || false
                  return (
                    <div className="d-flex flex-row flex-items-center gap-2">
                      {row.icon_url && !installation_icon && (
                        <GitHubAvatar src={row.icon_url} size={16} square={square_icon} />
                      )}
                      {row.icon_url && installation_icon && (
                        <InstallationAvatar
                          variant="small"
                          icon_url={row.icon_url}
                          icon_background_color={row?.icon_background_color}
                        />
                      )}
                      <div className="d-flex flex-column">
                        <Link href={row.href || '#'} className="f5 text-bold fgColor-default">
                          {row.name}
                        </Link>
                      </div>
                    </div>
                  )
                },
              },
              {
                header: () => {
                  return <span className="f6 fgColor-muted">Type</span>
                },
                field: 'actor_type',
                renderCell: row => {
                  return <span className="f5 fgColor-default px-1">{row.actor_type}</span>
                },
              },
              {
                header: () => {
                  return <span className="f6 fgColor-muted px-1 d-flex flex-1 flex-justify-end">Requests</span>
                },
                field: 'requests',
                renderCell: row => (
                  <span className="f5 fgColor-default px-1 d-flex flex-1 flex-justify-end">{row.requests}</span>
                ),
              },
            ]}
          />
        </Table.Container>
      )}
    </div>
  )
}
