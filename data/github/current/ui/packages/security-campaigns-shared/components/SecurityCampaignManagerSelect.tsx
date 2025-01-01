import {Box, ActionList} from '@primer/react'
import {SelectPanel} from '@primer/react/experimental'
import {GitHubAvatar} from '@github-ui/github-avatar'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import React, {useCallback, useMemo} from 'react'
import type {User} from '../types/user'
import {TriangleDownIcon} from '@primer/octicons-react'
import {useCampaignManagersQuery} from '../hooks/use-campaign-managers-query'

export type SecurityCampaignManagerSelectProps = {
  value: User | null
  onChange: (value: User | null) => void
  campaignManagersPath: string
  disabled?: boolean

  'aria-labelledby'?: string
}

export function SecurityCampaignManagerSelect({
  value,
  onChange,
  campaignManagersPath,
  disabled,
}: SecurityCampaignManagerSelectProps) {
  const {data} = useCampaignManagersQuery(campaignManagersPath)

  const potentialManagers = useMemo(() => {
    const managers = [...(data?.managers ?? [])]

    if (value && !managers.some(manager => manager.id === value.id)) {
      managers.push(value)
    }

    return managers
  }, [data, value])

  const [filter, setFilter] = React.useState('')

  const onSearchInputChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setFilter(event.target.value)
    },
    [setFilter],
  )

  const items = useMemo(
    () =>
      potentialManagers.map(manager => ({
        id: manager.id,
        text: manager.login,
        listItemContent: (withID = true) => (
          <Box sx={{display: 'flex', gap: '8px'}}>
            <Box sx={{display: 'flex', flexDirection: 'column', justifyContent: 'center'}}>
              <GitHubAvatar sx={{ml: '1px'}} size={16} src={manager.avatarUrl} alt="User avatar" />
            </Box>
            <Box
              id={withID ? `manager-action-list-item-${manager.id}` : undefined}
              sx={{display: 'flex', alignItems: 'baseline', flexGrow: 1}}
            >
              {manager.login}
            </Box>
          </Box>
        ),
      })),
    [potentialManagers],
  )

  const filteredItems = items.filter(item => item.text.toLowerCase().startsWith(filter.toLowerCase()))

  const selectedItem = items.find(item => item.id === value?.id)

  const handleSelectedChange = useCallback(
    (newValue: ItemInput | undefined) => {
      if (newValue === undefined || newValue.id === selectedItem?.id) {
        onChange(null)
        return
      }

      onChange(potentialManagers.find(manager => manager.id === newValue.id) ?? null)
    },
    [onChange, potentialManagers, selectedItem?.id],
  )

  return (
    // eslint-disable-next-line primer-react/no-system-props
    <SelectPanel
      title="Select a user"
      maxHeight="small"
      selectionVariant="instant"
      onCancel={() => setFilter('')}
      onSubmit={() => setFilter('')}
    >
      <SelectPanel.Button trailingAction={TriangleDownIcon} disabled={disabled}>
        {selectedItem?.listItemContent(false) || 'Select manager'}
      </SelectPanel.Button>

      <SelectPanel.Header>
        <SelectPanel.SearchInput onChange={onSearchInputChange} placeholder="Search for a user" />
      </SelectPanel.Header>

      {filteredItems.length === 0 ? (
        <SelectPanel.Message variant="empty" title={`No users found for "${filter}"`}>
          Try a different search term
        </SelectPanel.Message>
      ) : (
        <ActionList selectionVariant="single">
          {filteredItems.map(item => (
            <ActionList.Item
              key={item.id}
              onSelect={() => handleSelectedChange(item)}
              selected={item.id === selectedItem?.id}
              aria-labelledby={`manager-action-list-item-${item.id}`}
            >
              {item.listItemContent()}
            </ActionList.Item>
          ))}
        </ActionList>
      )}
    </SelectPanel>
  )
}
