import {GitHubAvatar} from '@github-ui/github-avatar'
import {ActionList} from '@primer/react'

import type {OwnerItem} from './OwnerDropdown'
import {Blankslate} from '@primer/react/experimental'

export function OwnerDropdownItemsV2({
  ownerItems,
  selectedOwner,
  onSelect,
  searchTerm,
}: {
  ownerItems: OwnerItem[]
  selectedOwner?: OwnerItem
  onSelect: (selectedOwner: OwnerItem) => void
  searchTerm: string
}) {
  if (ownerItems.length === 0) {
    return (
      <Blankslate>
        <Blankslate.Heading>No owners found for `{searchTerm}`</Blankslate.Heading>
        <Blankslate.Description>Adjust your search term to find other owners</Blankslate.Description>
      </Blankslate>
    )
  }

  const ownerListItems = ownerItems.map(item => {
    const {name, avatarUrl, disabled, customDisabledMessage} = item

    return (
      <ActionList.Item
        key={name}
        selected={name === selectedOwner?.name}
        disabled={disabled}
        onSelect={() => onSelect(item)}
        inactiveText={getDisabledMessage(disabled, customDisabledMessage)}
      >
        <ActionList.LeadingVisual>
          <GitHubAvatar src={avatarUrl} />
        </ActionList.LeadingVisual>
        {name}
      </ActionList.Item>
    )
  })

  return <ActionList selectionVariant="single">{ownerListItems}</ActionList>
}

const getDisabledMessage = (disabled: boolean, disabledMessage: string | null | undefined) => {
  if (!disabled) {
    return undefined
  }

  if (!disabledMessage) {
    return 'Insufficient permission'
  }

  // The messages come surrounded with parentheses from the server. It is a hack, but refactoring so that they are
  // just "raw" messages and also work with the existing dropdown implementation(s) is nontrivial.
  // See https://github.com/github/repos/issues/14931
  if (disabledMessage.startsWith('(') && disabledMessage.endsWith(')')) {
    return disabledMessage.substring(1, disabledMessage.length - 1)
  }

  return disabledMessage
}
