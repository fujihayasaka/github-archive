import {ActionList, ActionMenu} from '@primer/react'
import type {AlertsGroup} from '../types/get-alerts-groups-request'
import {RowsIcon} from '@primer/octicons-react'

export type AlertsGroupsMenuProps = {
  group: AlertsGroup
  setGroup: (group: AlertsGroup) => void
}

export function AlertsGroupsMenu({group, setGroup}: AlertsGroupsMenuProps): React.ReactNode {
  const groups: Array<{key: AlertsGroup; value: string}> = [
    {key: 'none', value: 'None'},
    {key: 'repository', value: 'Repository'},
  ]

  return (
    <ActionMenu>
      <ActionMenu.Button aria-label="Group by" leadingVisual={RowsIcon}>
        Group by: <strong>{groups.find(({key}) => key === group)?.value}</strong>
      </ActionMenu.Button>
      <ActionMenu.Overlay>
        <ActionList selectionVariant="single" role="menu">
          {groups.map(({key, value}) => (
            <ActionList.Item
              key={key}
              role="menuitemradio"
              selected={group === key}
              onSelect={() => {
                setGroup(key)
              }}
            >
              {value}
            </ActionList.Item>
          ))}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
