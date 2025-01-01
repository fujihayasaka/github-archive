import {GitHubAvatar} from '@github-ui/github-avatar'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {ActionList, ActionMenu, FormControl} from '@primer/react'
import {useEffect, useState} from 'react'

export interface OwnerItem {
  name: string
  avatarUrl: string
  displayName: string
  id: number
  type: 'User' | 'Organization'
}

interface SpacesOwnerDropdownProps {
  onSelect: (owner: OwnerItem) => void
}

export function SpacesOwnerDropdown({onSelect}: SpacesOwnerDropdownProps) {
  interface OwnersResult {
    owners: OwnerItem[]
  }

  const [ownerItems, setOwnerItems] = useState<OwnerItem[]>([])
  const [displayLoadingError, setDisplayLoadingError] = useState(false)
  const [selectedOwner, setSelectedOwner] = useState<OwnerItem | undefined>(undefined)

  const handleSelectOwner = (owner: OwnerItem) => {
    setSelectedOwner(owner)
    onSelect(owner)
  }

  useEffect(() => {
    const loadOwners = async () => {
      try {
        const result = await verifiedFetchJSON(`/github-copilot/chat/custom_copilots_owners`)
        const data = (await result.json()) as OwnersResult
        const owners = data?.owners
        if (!result.ok || !owners) {
          handleLoadingError()
          return
        }
        setOwnerItems(owners)
        if (owners[0]) {
          handleSelectOwner(owners[0])
        }
      } catch {
        handleLoadingError()
      }
    }

    void loadOwners()
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const handleLoadingError = () => {
    setOwnerItems([])
    setDisplayLoadingError(true)
  }

  const headerButton = () => {
    const displayName = selectedOwner?.name || 'Choose an owner'
    const buttonAvatar = selectedOwner ? (
      <GitHubAvatar src={selectedOwner.avatarUrl} key={selectedOwner.avatarUrl} />
    ) : undefined

    return (
      <ActionMenu.Button
        data-testid="owner-dropdown-anchor"
        alignContent="start"
        aria-label={displayName}
        leadingVisual={buttonAvatar}
      >
        {displayName}
      </ActionMenu.Button>
    )
  }

  return (
    <FormControl>
      <FormControl.Label>Owner</FormControl.Label>
      <ActionMenu>
        {headerButton()}
        <ActionMenu.Overlay responsiveVariant="fullscreen" width="large" maxHeight="large" sx={{overflow: 'auto'}}>
          <ActionList>
            <ActionList.Group sx={{maxHeight: 350, overflow: 'auto'}}>
              <ActionList selectionVariant="single">
                {ownerItems &&
                  ownerItems.map(item => {
                    const {name, avatarUrl, displayName} = item
                    return (
                      <ActionList.Item
                        key={name}
                        selected={name === selectedOwner?.name}
                        onSelect={() => handleSelectOwner(item)}
                      >
                        <ActionList.LeadingVisual>
                          <GitHubAvatar src={avatarUrl} />
                        </ActionList.LeadingVisual>
                        {name}
                        <ActionList.Description>{displayName}</ActionList.Description>
                      </ActionList.Item>
                    )
                  })}
                {!ownerItems.length && !displayLoadingError && (
                  <ActionList.Item key="fetching-owners" disabled>
                    Fetching owners…
                  </ActionList.Item>
                )}
                {displayLoadingError && (
                  <ActionList.Item key="error-fetching-owners" disabled sx={{color: 'danger.fg'}}>
                    An error occurred while loading owners. Please reopen the dialog to try again.
                  </ActionList.Item>
                )}
              </ActionList>
            </ActionList.Group>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>

      <FormControl.Caption>
        Where we will store your space. Once created the space is not transferable.
      </FormControl.Caption>
    </FormControl>
  )
}
