import {useState, useEffect} from 'react'
import {TriangleDownIcon, XIcon} from '@primer/octicons-react'
import {SelectPanel, Box, Button} from '@primer/react'

interface IdpGroup {
  id: number
  displayName: string
  hasGuestCollaborators?: boolean
}

export interface IdpConfig {
  isEnterpriseManagedUser: boolean
  canUseIdpGroups: boolean
  idpGroupsUrl?: string
  idpGroupsLimit?: number
}

interface InitialGroupState {
  memberManagementType?: 'manual' | 'idp_group'
  idpGroupId?: number | null
  idpGroupName?: string // Still need this for local UI display
}

interface BusinessTeamMembersManagementProps {
  idpConfig: IdpConfig
  initialState?: InitialGroupState
  enterpriseSlug: string
  onMemberManagementTypeChange: (type: 'manual' | 'idp_group') => void
  onIdpGroupChange: (id: number | null) => void
}

const DEFAULT_INITIAL_STATE: InitialGroupState = {
  memberManagementType: 'manual',
  idpGroupId: null,
  idpGroupName: '',
}

export function BusinessTeamMembersManagement({
  idpConfig,
  initialState = DEFAULT_INITIAL_STATE,
  enterpriseSlug,
  onMemberManagementTypeChange,
  onIdpGroupChange,
}: BusinessTeamMembersManagementProps) {
  const {isEnterpriseManagedUser, canUseIdpGroups, idpGroupsUrl, idpGroupsLimit = 500} = idpConfig
  const [memberManagementType, setMemberManagementType] = useState<'manual' | 'idp_group'>(
    initialState.memberManagementType || 'manual',
  )
  const [selectedIdpGroupId, setSelectedIdpGroupId] = useState<number | null>(initialState.idpGroupId || null)
  const [selectedIdpGroupName, setSelectedIdpGroupName] = useState<string>(initialState.idpGroupName || '')
  const [idpGroupsFilter, setIdpGroupsFilter] = useState('')
  const [isSelectPanelOpen, setIsSelectPanelOpen] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [idpGroups, setIdpGroups] = useState<IdpGroup[]>([])

  // Fetch IdP groups from the dedicated JSON API endpoint
  useEffect(() => {
    async function fetchIdpGroups() {
      if (isSelectPanelOpen && idpGroupsUrl && idpGroups.length === 0) {
        setIsLoading(true)
        try {
          const url = new URL(`/enterprises/${enterpriseSlug}/teams/group_suggestions`, window.location.origin)

          if (idpGroupsFilter) {
            url.searchParams.set('q', idpGroupsFilter)
          }

          // Set limit on number of groups to retrieve
          if (idpGroupsLimit) {
            url.searchParams.set('limit', idpGroupsLimit.toString())
          }

          const response = await fetch(url.toString(), {
            headers: {
              Accept: 'application/json',
              'X-Requested-With': 'XMLHttpRequest',
            },
          })

          if (!response.ok) {
            setIdpGroups([])
            return
          }

          const data = await response.json()
          setIdpGroups(data.groups)
        } catch {
          // If there's an error, just set empty array
          setIdpGroups([])
        } finally {
          setIsLoading(false)
        }
      }
    }

    fetchIdpGroups()
  }, [isSelectPanelOpen, idpGroupsUrl, idpGroupsFilter, idpGroupsLimit, idpGroups.length, enterpriseSlug])

  useEffect(() => {
    function handleMessage(event: MessageEvent) {
      if (event.origin !== window.location.origin) return

      try {
        const messageData = JSON.parse(event.data)
        if (messageData.type === 'idp-group-selected') {
          setSelectedIdpGroupId(messageData.id)
          setSelectedIdpGroupName(messageData.displayName)
          onIdpGroupChange(messageData.id)
        }
      } catch {
        // Ignore invalid JSON
      }
    }

    window.addEventListener('message', handleMessage)
    return () => window.removeEventListener('message', handleMessage)
  }, [onIdpGroupChange])

  // Only show the IdP group option if the user is an Enterprise Managed User and can use IdP groups
  const showIdpOption = isEnterpriseManagedUser && canUseIdpGroups

  const handleMemberManagementTypeChange = (type: 'manual' | 'idp_group') => {
    setMemberManagementType(type)
    onMemberManagementTypeChange(type)
  }

  const handleIdpGroupSelect = (selectedGroup: IdpGroup) => {
    setSelectedIdpGroupId(selectedGroup.id)
    setSelectedIdpGroupName(selectedGroup.displayName)
    onIdpGroupChange(selectedGroup.id)
    setIsSelectPanelOpen(false)
  }

  return (
    <div className="mt-4">
      <div className="mb-2 f4 text-bold">Manage members</div>
      <div className="form-group" style={{border: '1px solid #e1e4e8', padding: '16px', borderRadius: '6px'}}>
        <div className="form-checkbox mb-2 d-flex flex-items-center">
          <input
            id="manual-members"
            type="radio"
            name="memberManagementType"
            value="manual"
            checked={memberManagementType === 'manual'}
            onChange={() => handleMemberManagementTypeChange('manual')}
            data-testid="manual-member-management"
            style={{marginRight: '8px'}}
          />
          <div>
            <label htmlFor="manual-members" className="text-bold d-block">
              Selected members
            </label>
            <p className="note">Manage team by adding members manually</p>
          </div>
        </div>

        {showIdpOption && (
          <div className="form-checkbox d-flex flex-items-center">
            <input
              id="idp-group"
              type="radio"
              name="memberManagementType"
              value="idp_group"
              checked={memberManagementType === 'idp_group'}
              onChange={() => handleMemberManagementTypeChange('idp_group')}
              data-testid="idp-group-management"
              style={{marginRight: '8px'}}
            />
            <div>
              <label htmlFor="idp-group" className="text-bold d-block">
                Identity Provider Group
              </label>
              <p className="note">Manage team members using your identity provider group</p>
            </div>
          </div>
        )}

        {memberManagementType === 'idp_group' && (
          <div className="pl-4 mt-3" style={{maxWidth: '480px'}}>
            <Box sx={{my: 1}} data-testid="idp-group-select-panel">
              <SelectPanel
                title="Select Group"
                renderAnchor={({children, 'aria-labelledby': ariaLabelledBy, ...anchorProps}) => (
                  <Button
                    trailingAction={TriangleDownIcon}
                    aria-labelledby={ariaLabelledBy}
                    {...anchorProps}
                    data-testid="idp-group-selector"
                  >
                    {children ?? (selectedIdpGroupName || 'Select Group')}
                  </Button>
                )}
                placeholderText="Search groups"
                loading={isLoading}
                open={isSelectPanelOpen}
                onOpenChange={isOpen => {
                  setIsSelectPanelOpen(isOpen)
                }}
                items={idpGroups.map(group => ({
                  id: String(group.id),
                  text: group.displayName,
                  selected: selectedIdpGroupId === group.id,
                }))}
                selected={
                  selectedIdpGroupId
                    ? {
                        id: String(selectedIdpGroupId),
                        text: selectedIdpGroupName,
                      }
                    : undefined
                }
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                onSelectedChange={(selected: any) => {
                  if (selected && 'id' in selected) {
                    const selectedGroup = idpGroups.find(group => String(group.id) === selected.id)
                    if (selectedGroup) {
                      handleIdpGroupSelect(selectedGroup)
                    }
                  }
                }}
                onFilterChange={filter => {
                  setIdpGroupsFilter(filter)
                  // When the filter changes, we'll need to fetch groups again
                  setIdpGroups([])
                }}
                showItemDividers
                overlayProps={{
                  width: 'small',
                  height: 'xsmall',
                }}
              />
            </Box>

            {selectedIdpGroupId !== null && (
              <div className="Box mt-3">
                <div className="Box-row d-flex flex-items-center">
                  <div className="flex-auto overflow-hidden text-truncate">
                    <input
                      type="hidden"
                      name={`team[external_group_team][${selectedIdpGroupId}][display_name]`}
                      value={selectedIdpGroupName}
                      data-testid="selected-idp-group-input"
                    />
                    <strong data-testid="selected-idp-group">{selectedIdpGroupName}</strong>
                  </div>
                  <button
                    className="Box-btn-octicon btn-octicon"
                    type="button"
                    aria-label={`Remove ${selectedIdpGroupName}`}
                    onClick={() => {
                      // Update local state first
                      setSelectedIdpGroupId(null)
                      setSelectedIdpGroupName('')
                      // Then notify parent component
                      onIdpGroupChange(null)
                    }}
                  >
                    <XIcon />
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
