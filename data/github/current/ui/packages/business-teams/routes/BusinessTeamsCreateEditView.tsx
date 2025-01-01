import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Breadcrumbs, Button, FormControl, PageHeader, Stack, Textarea, Tooltip} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useNavigate} from '@github-ui/use-navigate'
import {useState} from 'react'
import {BusinessTeamNameInput} from '../components/BusinessTeamNameInput'
import {BusinessTeamOrgSelection} from '../components/BusinessTeamOrgSelection'
import {BusinessTeamMembersManagement} from '../components/BusinessTeamMembersManagement'
import type {IdpConfig} from '../components/BusinessTeamMembersManagement'
import {useMutation} from '@github-ui/react-query'
import {TrashIcon} from '@primer/octicons-react'
import TeamDeleteDialog from '../helpers/TeamDeleteDialog'
import {handleDelete} from '../helpers/handleDelete'
import type {Organization} from '../types'

import styles from '../styles/BusinessTeamsCreateEditView.module.css'
import {clsx} from 'clsx'

interface EnterpriseTeam {
  name: string
  description: string
  slug: string
  url: string
  organizationSelectionType: string
  selectedOrganizationsCount: number
  memberManagementType?: 'manual' | 'idp_group'
  externalGroupTeam?: {
    externalGroupId: number
    displayName: string
  }
}

export interface BusinessTeamsCreateAndEditPayload {
  // Update this type to reflect the data you place in payload in Rails
  enterpriseSlug: string
  enterpriseTeam?: EnterpriseTeam
  allOrgsCount: number
  enterpriseTeamsLimit: number
  enterpriseTeamsLimitReached: boolean
  enterpriseTeamsOrgAssignmentLimit: number
  baseUrl: string
  canSelectAllOrganizations: boolean
  canSelectOrganizationAssignmentType: boolean
  preventEditOrganizations: boolean
  maxTeamNameLength: number
  maxTeamDescriptionLength: number
  // Member management properties
  isMembersManagementEnabled?: boolean
  isEnterpriseManagedUser?: boolean
  canUseIdpGroups?: boolean
  idpGroupsUrl?: string
}

export function BusinessTeamsCreateEditView() {
  const payload = useRoutePayload<BusinessTeamsCreateAndEditPayload>()
  const teamsURL = payload.baseUrl
  const [description, setDescription] = useState<string>(payload.enterpriseTeam?.description || '')
  const [organizationSelectionType, setOrganizationSelectionType] = useState<string>(
    payload.enterpriseTeam?.organizationSelectionType ?? 'selected',
  )
  const [selectedOrganizations, setSelectedOrganizations] = useState<Organization[]>([])
  const [selectedOrganizationsCount, setSelectedOrganizationsCount] = useState<number>(
    payload.enterpriseTeam?.selectedOrganizationsCount ?? 0,
  )

  // Member management states
  const [memberManagementType, setMemberManagementType] = useState<'manual' | 'idp_group'>(
    payload.enterpriseTeam?.memberManagementType || 'manual',
  )
  const [selectedIdpGroupId, setSelectedIdpGroupId] = useState<number | null>(
    payload.enterpriseTeam?.externalGroupTeam?.externalGroupId || null,
  )
  // We still need to keep track of the display name for UI purposes
  // The name is only used for display in the UI and is not sent to the backend
  // When loading an existing team, we get the display name from the externalGroupTeam data
  const [selectedIdpGroupName, setSelectedIdpGroupName] = useState<string>(
    payload.enterpriseTeam?.externalGroupTeam?.displayName || '',
  )

  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false)
  const [selectedTeams, setSelectedTeams] = useState<Set<{slug: string; name: string}>>(() => new Set())

  const editMode = payload.enterpriseTeam !== undefined

  const navigate = useNavigate()

  interface FormDataResponse {
    data: {
      redirect?: string
      error?: string
    }
  }

  const {mutate, isError, isPending, data} = useMutation<FormDataResponse, Error, FormData>({
    mutationKey: ['business-teams', 'create-edit-team'],
    mutationFn: async (formData: FormData) => {
      const url = editMode ? `${payload.enterpriseTeam?.url}` : teamsURL
      formData.append('organizationSelectionType', organizationSelectionType)

      // Add member management data
      formData.append('memberManagementType', memberManagementType)
      if (memberManagementType === 'idp_group' && selectedIdpGroupId) {
        formData.append('idpGroupId', selectedIdpGroupId.toString())
        // We don't send idpGroupName since the backend looks up the display name from the external group
      }

      if (!editMode) {
        formData.append('selectedOrganizationIds', JSON.stringify(selectedOrganizations.map(org => org.id)))
      }

      const result = await verifiedFetch(url, {
        method: editMode ? 'PUT' : 'POST',
        headers: {Accept: 'application/json'},
        body: formData,
      })

      if (result.ok) {
        const json = await result.json()
        if (json.data && json.data.redirect) {
          return json
        }
      } else if (result.status >= 400 && result.status < 500) {
        const json = await result.json()
        if (json.data && json.data.error) {
          return json
        }
      }
      throw new Error(`${result.status} on ${result.url}, unexpected status or payload`)
    },
    onSuccess: result => {
      if (result.data.redirect) {
        const redirectUrl = result.data.redirect + (editMode ? '' : '?created=1')
        const relUrl = redirectUrl.startsWith(window.location.origin)
          ? redirectUrl.replace(window.location.origin, '')
          : redirectUrl
        // TODO if we use navigate from useNavigate, the team members page cannot read payload fields, this should be investigated
        window.location.replace(relUrl)
      }
    },
  })

  const [teamName, setTeamName] = useState<string>(payload.enterpriseTeam?.name ?? '')
  const handleTeamNameChange = (newBusinessTeamName: string) => {
    setTeamName(newBusinessTeamName)
  }

  function handleSetSelectedOrganizations(newSelectedOrganizations: Organization[]) {
    setSelectedOrganizations(newSelectedOrganizations)
    setSelectedOrganizationsCount(newSelectedOrganizations.length)
  }

  function handleSelectionChange(value: string) {
    setOrganizationSelectionType(value)
  }

  // Member management handlers
  const handleMemberManagementTypeChange = (type: 'manual' | 'idp_group') => {
    setMemberManagementType(type)
  }

  const handleIdpGroupChange = (id: number | null) => {
    setSelectedIdpGroupId(id)
    if (id === null) {
      setSelectedIdpGroupName('')
    }
    // Note: We don't need to update the name here when selecting a group
    // because the BusinessTeamMembersManagement component already has the name
  }

  const handleDeleteConfirmation = async () => {
    await handleDelete(payload.enterpriseSlug, selectedTeams, () => {})
    setIsDeleteDialogOpen(false)
  }

  return (
    <form
      onSubmit={e => {
        e.preventDefault()
        const formData = new FormData()
        formData.append('teamName', teamName ?? '')
        formData.append('teamDescription', description)
        mutate(formData)
      }}
    >
      {isError && (
        <Banner
          hideTitle
          title="Failed to create or edit team"
          data-testid="flash-error"
          variant="critical"
          className="mb-3"
        >
          {`Something went wrong while ${editMode ? 'updating' : 'creating'} the team. Please try again later.`}
        </Banner>
      )}

      {data?.data.error && (
        <Banner
          hideTitle
          title="Failed to create or edit team"
          data-testid="flash-error"
          variant="critical"
          className="mb-3"
        >
          {data.data.error}
        </Banner>
      )}

      <div className="d-flex flex-column flex-items-start flex-self-stretch">
        <div className="width-full border-bottom color-border-default">
          <Breadcrumbs>
            <Breadcrumbs.Item href={teamsURL}>Enterprise teams</Breadcrumbs.Item>
            {editMode ? (
              <Breadcrumbs.Item selected>Edit Enterprise team</Breadcrumbs.Item>
            ) : (
              <Breadcrumbs.Item selected>Create Enterprise team</Breadcrumbs.Item>
            )}
          </Breadcrumbs>
          <PageHeader className="hide-sm pb-1 mb-1 mt-2">
            <PageHeader.TitleArea>
              <PageHeader.Title as="h1">
                {editMode ? 'Edit Enterprise team' : 'Create Enterprise team'}
              </PageHeader.Title>
            </PageHeader.TitleArea>
          </PageHeader>
        </div>

        <Stack gap="normal" className={clsx('mt-3', styles.Stack)}>
          <BusinessTeamNameInput
            businessSlug={payload.enterpriseSlug}
            businessTeamName={teamName}
            businessTeamSlug={payload.enterpriseTeam?.slug}
            onChange={handleTeamNameChange}
            onValidityChange={() => {}}
            readonly={false}
            hideBlankCheck={false}
            editMode={editMode}
            maxTeamNameLength={payload.maxTeamNameLength}
          />

          <FormControl id="business-team-description">
            <FormControl.Label>Description</FormControl.Label>
            <div style={{position: 'relative'}} className="width-full">
              <Textarea
                data-testid="business-team-description"
                resize="none"
                sx={{width: '100%', height: '100px', paddingBottom: '20px'}}
                placeholder="What is this team all about?"
                value={description}
                onChange={e => setDescription(e.target.value)}
              />
              <span
                data-testid="team-description-counter"
                style={{
                  position: 'absolute',
                  bottom: 'var(--base-size-6)',
                  right: 'var(--base-size-12)',
                  color: 'var(--fgColor-muted)',
                  fontSize: 'var(--text-body-size-small)',
                  pointerEvents: 'none',
                  zIndex: 2,
                }}
              >
                {description.length}/{payload.maxTeamDescriptionLength}
              </span>
            </div>
            <FormControl.Caption>
              What is this team all about? The maximum length is {payload.maxTeamDescriptionLength} characters
            </FormControl.Caption>
          </FormControl>
        </Stack>
      </div>

      {payload.canSelectOrganizationAssignmentType && (
        <div className="width-full mt-4">
          <BusinessTeamOrgSelection
            enterpriseSlug={payload.enterpriseSlug}
            selectedOrganizations={selectedOrganizations}
            selectedOrganizationsCount={selectedOrganizationsCount}
            organizationSelectionType={organizationSelectionType}
            allOrgsCount={payload.allOrgsCount}
            enterpriseTeamsOrgAssignmentLimit={payload.enterpriseTeamsOrgAssignmentLimit}
            canSelectAllOrganizations={payload.canSelectAllOrganizations}
            handleSelectionChange={handleSelectionChange}
            handleSetSelectedOrganizations={handleSetSelectedOrganizations}
            preventEditOrganizations={payload.preventEditOrganizations}
          />
        </div>
      )}
      {payload.isMembersManagementEnabled && payload.canUseIdpGroups && (
        <div className="width-full mt-4">
          <BusinessTeamMembersManagement
            idpConfig={
              {
                isEnterpriseManagedUser: payload.isEnterpriseManagedUser || false,
                canUseIdpGroups: payload.canUseIdpGroups || false,
                idpGroupsUrl: payload.idpGroupsUrl,
              } as IdpConfig
            }
            initialState={{
              memberManagementType,
              idpGroupId: selectedIdpGroupId,
              idpGroupName: selectedIdpGroupName,
            }}
            enterpriseSlug={payload.enterpriseSlug}
            onMemberManagementTypeChange={handleMemberManagementTypeChange}
            onIdpGroupChange={handleIdpGroupChange}
          />
        </div>
      )}

      <div className="mt-4 d-flex flex-row">
        {!editMode && payload.enterpriseTeamsLimitReached ? (
          <Tooltip
            text={`Cannot add more teams, you've reached the ${payload.enterpriseTeamsLimit}-team limit.`}
            direction="n"
          >
            <Button variant="default" inactive>
              Create Enterprise team
            </Button>
          </Tooltip>
        ) : (
          <Button data-testid="submit-button" variant="primary" type="submit" inactive={isPending} loading={isPending}>
            {editMode ? 'Update team' : 'Create Enterprise team'}
          </Button>
        )}
        <div className="ml-2">
          <Button variant="default" onClick={() => navigate(teamsURL)}>
            Cancel
          </Button>
        </div>
      </div>

      {editMode && (
        <Stack gap="condensed" className="mt-5">
          <div className="text-medium text-bold">Additional options</div>

          <Stack gap="normal" className={clsx('p-3 border rounded-2 width-full color-shadow-small', styles.Stack_1)}>
            <div className="flex-1 d-flex flex-column">
              <div className="text-medium text-bold mb-0">Delete Team</div>
              <div className="text-small" style={{color: 'var(--fgColor-muted)'}}>
                This action cannot be undone and will remove this team&apos;s configuration, including its membership
                list and permission settings.
              </div>
            </div>
            <Button
              data-testid="delete-team"
              variant="danger"
              leadingVisual={TrashIcon}
              onClick={() => {
                if (payload.enterpriseTeam) {
                  setSelectedTeams(new Set([{slug: payload.enterpriseTeam.slug, name: payload.enterpriseTeam.name}]))
                }
                setIsDeleteDialogOpen(true)
              }}
            >
              Delete team
            </Button>
          </Stack>
        </Stack>
      )}

      <TeamDeleteDialog
        isOpen={isDeleteDialogOpen}
        onClose={() => setIsDeleteDialogOpen(false)}
        onConfirm={handleDeleteConfirmation}
        selectedTeams={selectedTeams}
      />
    </form>
  )
}
