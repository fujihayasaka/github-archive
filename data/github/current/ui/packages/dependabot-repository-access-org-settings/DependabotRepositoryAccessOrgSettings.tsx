import {useState} from 'react'
import {MultiSelectReposPicker} from '@github-ui/repos-picker'
import type {PickerRepository, PickerScope} from '@github-ui/repos-picker'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {ActionMenuSelector} from '@github-ui/action-menu-selector'

export type DependabotAccess = 'public' | 'internal'
export interface DependabotRepositoryAccessOrgSettingsProps {
  allowedRepositoryPickerScope: PickerScope
  allowedRepositories: PickerRepository[]
  accessLevel?: DependabotAccess
  setRepositoryAccessUrl?: string
  setAllowedRepositoriesUrl: string
}

const orderedAccessValues: DependabotAccess[] = ['public', 'internal']
const displayAccessValues: Record<DependabotAccess, string> = {
  public: 'Public repositories only',
  internal: 'Public and internal repositories only',
}

export function DependabotRepositoryAccessOrgSettings(props: DependabotRepositoryAccessOrgSettingsProps) {
  const {allowedRepositoryPickerScope, setRepositoryAccessUrl, setAllowedRepositoriesUrl} = props
  const showAccessLevelSelector = Boolean(setRepositoryAccessUrl)

  const [allowed, setAllowed] = useState<PickerRepository[]>(props.allowedRepositories || [])
  const [accessLevel, setAccessLevel] = useState<DependabotAccess>(props.accessLevel || 'public')
  const updateRepositoryAccessLevel = async (newAccessLevel: DependabotAccess) => {
    if (!setRepositoryAccessUrl) {
      return
    }

    await verifiedFetch(setRepositoryAccessUrl, {
      method: 'PUT',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({accessLevel: newAccessLevel}),
    })

    setAccessLevel(newAccessLevel)
  }

  const updateAllowedRepositories = async (newRepoSelection: PickerRepository[]) => {
    await verifiedFetch(setAllowedRepositoriesUrl, {
      method: 'PUT',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({repositoryIds: newRepoSelection.map(repo => repo.id)}),
    })
    setAllowed(newRepoSelection)
  }

  return (
    <>
      <div className="border color-border-default rounded-1 p-3 mb-3">
        {showAccessLevelSelector && (
          <div className="d-flex flex-items-center flex-wrap border-bottom pb-3 mb-3">
            <div className="flex-1" style={{maxWidth: '100%'}}>
              <div className="text-bold">Repository access</div>
              <div className="f6 color-fg-muted">Choose which repositories Dependabot can access.</div>
            </div>
            <div
              className="d-flex flex-items-center"
              style={{marginLeft: 'auto'}}
              data-testid="dependabot-repository-access-selector"
            >
              <ActionMenuSelector
                currentSelection={accessLevel}
                orderedValues={orderedAccessValues}
                displayValues={displayAccessValues}
                onSelect={updateRepositoryAccessLevel}
              />
            </div>
          </div>
        )}

        <div className="d-flex flex-items-center flex-wrap">
          <div className="flex-1" style={{maxWidth: '100%'}}>
            <div className="text-bold">
              Select {showAccessLevelSelector && <span> additional </span>}
              <span>repositories</span>
            </div>
            <div className="f6 color-fg-muted">
              Choose {showAccessLevelSelector && <span> additional </span>}
              <span>repositories Dependabot can access.</span>
            </div>
          </div>
          <div data-testid="dependabot-allowed-repository-selector">
            <MultiSelectReposPicker
              scope={allowedRepositoryPickerScope}
              onSubmit={updateAllowedRepositories}
              selected={allowed}
            />
          </div>
        </div>
      </div>
    </>
  )
}
