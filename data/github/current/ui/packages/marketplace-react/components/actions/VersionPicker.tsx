import {Dialog, ActionList} from '@primer/react'
import {marketplaceActionPath} from '@github-ui/paths'
import type {Release} from '../../types'
import type {ActionListing} from '@github-ui/marketplace-common'
import {Link} from '@github-ui/react-core/link'

interface VersionPickerProps {
  action: ActionListing
  selectedRelease?: Release
  releases: Release[]
  isOpen: boolean
  onClose: () => void
}

export function VersionPicker(props: VersionPickerProps) {
  const {action, selectedRelease, releases, isOpen, onClose} = props

  return (
    <>
      {isOpen && (
        <Dialog title="Choose a version" width="large" onClose={onClose}>
          <ActionList showDividers variant="full" data-testid="version-picker-dialog">
            {releases.map(release => {
              const isActiveRelease = selectedRelease && release.tagName === selectedRelease.tagName
              return (
                <ActionList.LinkItem
                  as={Link}
                  key={release.tagName}
                  to={`${marketplaceActionPath({slug: action.slug || ''})}?version=${release.tagName}`}
                  active={isActiveRelease}
                  data-testid={isActiveRelease ? 'selected-version' : ''}
                  onClick={onClose}
                >
                  <span className="text-semibold">{release.tagName}</span>
                  {release.name && release.name !== release.tagName && (
                    <ActionList.Description variant="block">{release.name}</ActionList.Description>
                  )}
                </ActionList.LinkItem>
              )
            })}
          </ActionList>
        </Dialog>
      )}
    </>
  )
}
