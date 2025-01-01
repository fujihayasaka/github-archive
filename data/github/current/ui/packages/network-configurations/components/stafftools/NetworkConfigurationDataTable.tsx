import {DataTable, Table} from '@primer/react/experimental'
import {useState} from 'react'
import {RunnerGroupDialog} from './RunnerGroupsDialog'
import type {NetworkConfiguration} from '../../classes/network-configuration'
import {Link, Truncate} from '@primer/react'
import {useNavigate} from '@github-ui/use-navigate'
import {staffToolsPrivateNetworksLink} from '../../helpers/stafftools-helpers'

interface NetworkConfigurationDataTableProps {
  networkConfigurations: NetworkConfiguration[]
  isEnterprise: boolean
  actor: string
}

export function StaffToolsNetworkConfigurationDataTable(props: NetworkConfigurationDataTableProps) {
  const [showRunnerGroupDialog, setShowRunnerGroupDialog] = useState<string | null>(null)
  const navigate = useNavigate()

  return (
    <Table.Container>
      <DataTable
        data={props.networkConfigurations}
        columns={[
          {
            header: 'ID',
            field: 'id',
            rowHeader: true, //truncate to first 8
            renderCell: row => {
              return (
                <Truncate title={row.id} inline>
                  {row.id}
                </Truncate>
              )
            },
          },
          {
            header: 'Name',
            field: 'name',
          },
          {
            header: 'Created On',
            field: 'createdOn',
          },
          {
            header: 'Compute Service',
            field: 'computeService',
          },
          {
            header: 'Runner Groups',
            field: 'runnerGroups',
            renderCell: row => {
              return row.runnerGroups.length === 0 ? (
                0
              ) : (
                <>
                  <Link onClick={() => setShowRunnerGroupDialog(row.id)}>{row.runnerGroups.length}</Link>
                  {showRunnerGroupDialog === row.id && (
                    <RunnerGroupDialog
                      closeDialog={() => setShowRunnerGroupDialog(null)}
                      runnerGroups={row.runnerGroups}
                    />
                  )}
                </>
              )
            },
          },
          {
            header: 'Private Networks',
            field: 'networkSettingReferences',
            renderCell: row => {
              return row.networkSettingReferences.length === 0 ? (
                0
              ) : (
                <Link onClick={() => navigate(staffToolsPrivateNetworksLink(props.isEnterprise, props.actor, row.id))}>
                  {row.networkSettingReferences.length}
                </Link>
              )
            },
          },
        ]}
      />
    </Table.Container>
  )
}
