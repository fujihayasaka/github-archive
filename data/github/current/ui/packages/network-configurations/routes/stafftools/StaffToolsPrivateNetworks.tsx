import type {PrivateNetwork} from '../../classes/private-network'
import {DataTable, Table} from '@primer/react/experimental'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Breadcrumbs, Truncate} from '@primer/react'
import {useNavigate} from '@github-ui/use-navigate'
import {staffToolsNetworkConfigurationLink} from '../../helpers/stafftools-helpers'

export interface StaffToolsPrivateNetworksPayload {
  privateNetworks: PrivateNetwork[]
  isEnterprise: boolean
  actor: string
}

export function StaffToolsPrivateNetworks() {
  const payload = useRoutePayload<StaffToolsPrivateNetworksPayload>()
  const navigate = useNavigate()

  return (
    <>
      <Breadcrumbs sx={{pb: 3}}>
        <Breadcrumbs.Item
          onClick={() => navigate(staffToolsNetworkConfigurationLink(payload.isEnterprise, payload.actor))}
        >
          Hosted Compute Networking
        </Breadcrumbs.Item>
        <Breadcrumbs.Item selected>Private Networks</Breadcrumbs.Item>
      </Breadcrumbs>
      <Table.Container>
        <DataTable
          data={payload.privateNetworks}
          columns={[
            {
              header: 'ID',
              field: 'id',
              rowHeader: true,
              renderCell: row => {
                return (
                  <Truncate title={row.id} inline>
                    {row.id}
                  </Truncate>
                )
              },
            },
            {
              header: 'Subscription',
              field: 'subscription',
            },
            {
              header: 'Virtual Network',
              field: 'virtualNetwork',
            },
            {
              header: 'Location',
              field: 'location',
            },
            {
              header: 'Subnet',
              field: 'subnet',
            },
            {
              header: 'Resource Group',
              field: 'resourceGroup',
            },
            {
              header: 'Resource Name',
              field: 'resourceName',
            },
          ]}
        />
      </Table.Container>
    </>
  )
}
