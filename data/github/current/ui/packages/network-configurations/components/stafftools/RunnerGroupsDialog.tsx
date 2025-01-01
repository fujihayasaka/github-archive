import {Dialog} from '@primer/react/deprecated'
import type {RunnerGroup} from '../../classes/network-configuration'
import {DataTable, Table} from '@primer/react/experimental'
import {Box} from '@primer/react'

interface RunnerGroupsDialogProps {
  closeDialog: () => void
  runnerGroups: RunnerGroup[]
}

export function RunnerGroupDialog(props: RunnerGroupsDialogProps) {
  return (
    <Dialog isOpen onDismiss={() => props.closeDialog()}>
      <Dialog.Header>Runner Groups</Dialog.Header>
      <Box sx={{p: 3}}>
        <Table.Container>
          <DataTable
            data={props.runnerGroups}
            columns={[
              {
                header: 'ID',
                field: 'id',
                rowHeader: true,
              },
              {
                header: 'Name',
                field: 'name',
              },
            ]}
          />
        </Table.Container>
      </Box>
    </Dialog>
  )
}
