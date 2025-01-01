import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Breadcrumbs, Button, FormControl, PageHeader, Textarea} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useNavigate} from '@github-ui/use-navigate'
import {useRef, useState} from 'react'
import {BusinessTeamNameInput} from '../components/BusinessTeamNameInput'
import {BusinessTeamOrgSelection} from '../components/BusinessTeamOrgSelection'
import {useMutation} from '@github-ui/react-query'
import {TrashIcon} from '@primer/octicons-react'
import TeamDeleteDialog from '../helpers/TeamDeleteDialog'
import {handleDelete} from '../helpers/handleDelete'
import type {Organization} from '../types'

interface EnterpriseTeam {
  name: string
  description: string
  slug: string
  url: string
  organizationSelectionType: string
  selectedOrganizations?: Organization[]
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
}

export function BusinessTeamsCreateEditView() {
  const payload = useRoutePayload<BusinessTeamsCreateAndEditPayload>()
  const teamsURL = payload.baseUrl
  const descriptionRef = useRef<HTMLTextAreaElement>(null)
  const [organizationSelectionType, setOrganizationSelectionType] = useState<string>(
    payload.enterpriseTeam?.organizationSelectionType ?? 'selected',
  )
  const [selectedOrganizations, setSelectedOrganizations] = useState(
    payload.enterpriseTeam?.selectedOrganizations || [],
  )

  const [isDeleteDialogOpen, setIsDeleteDialogOpen] = useState(false)
  const [selectedTeams, setSelectedTeams] = useState<Set<string>>(new Set())

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
      formData.append('selectedOrganizationIds', JSON.stringify(selectedOrganizations.map(org => org.id)))
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
        const redirectUrl = result.data.redirect
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
  }

  function handleSelectionChange(value: string) {
    setOrganizationSelectionType(value)
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
        formData.append('teamDescription', descriptionRef.current?.value ?? '')
        mutate(formData)
      }}
      className="m-1 p-1"
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

      <div className="mt-1 d-flex flex-column flex-items-start flex-self-stretch">
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

        <div className="mt-3 d-flex flex-column flex-items-start flex-self-stretch">
          <BusinessTeamNameInput
            businessSlug={payload.enterpriseSlug}
            businessTeamName={teamName}
            businessTeamSlug={payload.enterpriseTeam?.slug}
            onChange={handleTeamNameChange}
            onValidityChange={() => {}}
            readonly={false}
            hideBlankCheck={false}
            editMode={editMode}
          />
          <FormControl sx={{mt: 4}} id="business-team-description">
            <FormControl.Label>Description</FormControl.Label>
            <Textarea
              data-testid="business-team-description"
              ref={descriptionRef}
              sx={{width: '450px', height: '100px'}}
              placeholder="What is this team all about?"
              defaultValue={editMode ? payload.enterpriseTeam?.description : undefined}
            />
            <FormControl.Caption>What is this team all about?</FormControl.Caption>
          </FormControl>
        </div>
      </div>

      {payload.canSelectOrganizationAssignmentType && (
        <div className="width-full mt-3">
          <BusinessTeamOrgSelection
            enterpriseSlug={payload.enterpriseSlug}
            selectedOrganizations={selectedOrganizations}
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

      <div className="mt-4 d-flex flex-row">
        <Button
          data-testid="submit-button"
          variant="primary"
          type="submit"
          disabled={isPending || (!editMode && payload.enterpriseTeamsLimitReached)}
          loading={isPending}
        >
          {editMode ? 'Update team' : 'Create Enterprise team'}
        </Button>
        <div className="ml-2">
          <Button variant="default" onClick={() => navigate(teamsURL)}>
            Cancel
          </Button>
        </div>
      </div>

      {editMode && (
        <div className="mt-4">
          <div className="font-weight-bold mb-2">Additional options</div>
          <div className="d-flex flex-row align-items-center p-3 border border-default rounded-2 width-full">
            <div className="flex-1 d-flex flex-column">
              <div className="font-weight-bold mb-1">Delete Team</div>
              <div className="font-size-1 text-muted">Team restoration is possible for 90 days post-deletion.</div>
            </div>
            <Button
              data-testid="delete-team"
              variant="danger"
              leadingVisual={TrashIcon}
              onClick={() => {
                if (payload.enterpriseTeam) {
                  setSelectedTeams(new Set([payload.enterpriseTeam.slug]))
                }
                setIsDeleteDialogOpen(true)
              }}
            >
              Delete team
            </Button>
          </div>
        </div>
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
