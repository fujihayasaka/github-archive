import {ActionList, ActionMenu} from '@primer/react'
import {useCallback, useMemo} from 'react'

import {useClickLogging} from '../../../common/hooks/use-click-logging'
import styles from './GroupMenu.module.css'

export type GroupKey = 'status' | 'severity'

interface GroupMenuProps {
  groupKey: GroupKey
  onGroupKeyChanged: (key: GroupKey) => void
}

export default function GroupMenu({groupKey, onGroupKeyChanged}: GroupMenuProps): JSX.Element {
  const {logClick} = useClickLogging({category: 'CodeScanningReport.Group'})

  const onItemSelected = useCallback(
    (key: GroupKey) => {
      logClick({action: 'select group option', label: key})
      onGroupKeyChanged(key)
    },
    [logClick, onGroupKeyChanged],
  )

  const groupOptions = useMemo(() => {
    return {
      status: {
        label: 'State',
      },
      severity: {
        label: 'Severity',
      },
    }
  }, [])

  return (
    <ActionMenu>
      <ActionMenu.Button variant="invisible" data-testid="group-menu-button">
        <span className={styles.GroupMenuLabel}>Group by: </span>
        {groupOptions[groupKey]?.label}
      </ActionMenu.Button>
      <ActionMenu.Overlay>
        <ActionList selectionVariant="single">
          <ActionList.Group>
            <ActionList.GroupHeading>Group by</ActionList.GroupHeading>
            {Object.entries(groupOptions).map(([key, {label}]) => {
              return (
                <ActionList.Item
                  key={`group-${key}`}
                  role="menuitemradio"
                  selected={key === groupKey}
                  onSelect={() => onItemSelected(key as GroupKey)}
                >
                  {label}
                </ActionList.Item>
              )
            })}
          </ActionList.Group>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
