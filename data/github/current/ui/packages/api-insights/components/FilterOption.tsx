import {ActionMenu, ActionList} from '@primer/react'
import {useReplaceSearchParams} from '../hooks/UseReplaceSearchParams'
import type {Group} from '../types/filter-types'

export interface FilterOptionProps {
  name: string
  group: Group
}

export function FilterOption({name, group}: FilterOptionProps) {
  const {replaceSearchParam} = useReplaceSearchParams()
  const {selected_value} = group

  const selectedItem = group.options.find(option => option.value === selected_value)

  return (
    <ActionMenu>
      <ActionMenu.Button>
        <span className="fgColor-muted">
          {name}
          {selectedItem && ': '}
        </span>
        {selectedItem && <span>{selectedItem.name}</span>}
      </ActionMenu.Button>
      <ActionMenu.Overlay width="auto">
        <ActionList selectionVariant="multiple">
          <ActionList.Group key={group.query_param}>
            {group.name && <ActionList.GroupHeading>{group.name}</ActionList.GroupHeading>}
            {group.options.map(option => {
              return (
                <ActionList.Item
                  key={option.name}
                  selected={selected_value === option.value}
                  disabled={option.disabled}
                  onSelect={() => {
                    replaceSearchParam(group.query_param, option.value)
                  }}
                >
                  {option.name}
                </ActionList.Item>
              )
            })}
          </ActionList.Group>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
