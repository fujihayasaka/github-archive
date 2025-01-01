import type {
  ProjectPickerProject$key,
  ProjectPickerProject$data as Project,
} from '@github-ui/item-picker/ProjectPickerProject.graphql'

// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useCallback, useMemo, useState, type HTMLAttributes, type ReactNode, forwardRef} from 'react'
import {graphql, readInlineData, useRelayEnvironment, useFragment} from 'react-relay'
import {ConnectionHandler} from 'relay-runtime'

import {LABELS} from '../../constants/labels'
import {ERRORS} from '../../constants/errors'
import {commitDeleteIssueProjectsMutation} from '../../mutations/delete-issue-projects-mutation'

import {ProjectItemSection} from './ProjectItemSection'
import {ReadonlySectionHeader} from '../ReadonlySectionHeader'
import {Section} from '../Section'
import {SectionHeader} from '../SectionHeader'
import type {
  ProjectsSectionFragment$data,
  ProjectsSectionFragment$key,
} from './__generated__/ProjectsSectionFragment.graphql'
import {ActionList, Box, Button} from '@primer/react'
import {ChevronDownIcon, ChevronUpIcon} from '@primer/octicons-react'
import {commitUpdateIssueProjectsMutation} from '@github-ui/item-picker/updateIssueProjectsMutation'
import {ProjectPickerProjectFragment, ProjectPicker} from '@github-ui/item-picker/ProjectPicker'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'

const ReadonlyProjectsSectionHeader = () => <ReadonlySectionHeader title={LABELS.sectionTitles.projects} />
const ProjectsSectionHeader = forwardRef<HTMLButtonElement, HTMLAttributes<HTMLElement>>((props, ref) => (
  <SectionHeader ref={ref} id={props.id} title={LABELS.sectionTitles.projects} buttonProps={props} />
))
ProjectsSectionHeader.displayName = 'ProjectsSectionHeader'

type ProjectsSectionProps = {
  sectionHeader: JSX.Element
  hasItems: boolean
  children?: ReactNode
}
const ProjectsSection = ({sectionHeader, hasItems, children}: ProjectsSectionProps) => {
  return (
    <Section
      id={`sidebar-projects-section`}
      sectionHeader={sectionHeader}
      emptyText={hasItems ? undefined : LABELS.emptySections.projects}
    >
      {children}
    </Section>
  )
}

export const ProjectsSectionFallback = () => (
  <Section
    id={'projects-section-fallback'}
    sectionHeader={<ReadonlySectionHeader title={ERRORS.projectsUnavailable} />}
    emptyText={ERRORS.tryAgainLater}
  />
)

type CreateIssueProjectsSectionProps = {
  owner: string
  repo: string
  projects: Project[]
  readonly: boolean
  onSelectionChange: (value: Project[]) => void
  shortcutEnabled: boolean
}
export const CreateIssueProjectsSection = ({
  owner,
  repo,
  projects,
  readonly,
  onSelectionChange,
  ...sharedConfigProps
}: CreateIssueProjectsSectionProps) => {
  const headingLabelId = 'create-issue-sidebar-projects-section-heading'
  const sectionHeader = readonly ? (
    <ReadonlyProjectsSectionHeader />
  ) : (
    <ProjectPicker
      pickerId={'create-issue-projects-picker'}
      owner={owner}
      repo={repo}
      selectedProjects={projects}
      readonly={readonly}
      onSave={onSelectionChange}
      anchorElement={props => <ProjectsSectionHeader {...props} id={headingLabelId} />}
      {...sharedConfigProps}
    />
  )

  return (
    <ErrorBoundary fallback={<ProjectsSectionFallback />}>
      <ProjectsSection sectionHeader={sectionHeader} hasItems={projects.length > 0}>
        {projects.length > 0 && (
          <ActionList aria-labelledby={headingLabelId} sx={{py: 0}} variant="full">
            {projects.map(project => (
              <ActionList.LinkItem key={project.id} href={project.url} sx={{wordBreak: 'break-word'}}>
                {project.title}
              </ActionList.LinkItem>
            ))}
          </ActionList>
        )}
      </ProjectsSection>
    </ErrorBoundary>
  )
}

type EditIssueProjectsSectionProps = {
  issueOrPullRequest: ProjectsSectionFragment$key
  selectedProjectId?: string
  allowedProjectOwner?: string
  onIssueUpdate?: () => void
  insideSidePanel?: boolean
}

const projectSectionFragment = graphql`
  fragment ProjectsSectionFragment on IssueOrPullRequest
  @argumentDefinitions(allowedOwner: {type: "String", defaultValue: null}) {
    ... on Issue {
      number
      repository {
        name
        owner {
          login
        }
        isArchived
      }
      id
      projectItemsNext(first: 10, allowedOwner: $allowedOwner) @connection(key: "ProjectSection_projectItemsNext") {
        edges {
          node {
            id
            ...ProjectItemSection
            project {
              ...ProjectPickerProject
              closed
              title
              id
            }
          }
        }
      }
      viewerCanUpdateMetadata
    }
    ... on PullRequest {
      number
      repository {
        name
        owner {
          login
        }
        isArchived
      }
      id
      projectItemsNext(first: 10, allowedOwner: $allowedOwner) @connection(key: "ProjectSection_projectItemsNext") {
        edges {
          node {
            id
            ...ProjectItemSection
            project {
              closed
              ...ProjectPickerProject
              title
              id
            }
          }
        }
      }
      viewerCanUpdate
    }
  }
`

export function EditIssueProjectsSection(props: EditIssueProjectsSectionProps) {
  const projectsSectionData = useFragment(projectSectionFragment, props.issueOrPullRequest)

  if (!projectsSectionData.projectItemsNext) return <ProjectsSectionFallback />

  return <EditIssueProjectsSectionInternal projectsSectionData={projectsSectionData} {...props} />
}

type EditIssueProjectsSectionInternalType = {
  projectsSectionData: ProjectsSectionFragment$data
} & EditIssueProjectsSectionProps

const EditIssueProjectsSectionInternal = ({
  projectsSectionData,
  allowedProjectOwner,
  onIssueUpdate,
  insideSidePanel,
  selectedProjectId,
}: EditIssueProjectsSectionInternalType) => {
  const {addToast} = useToastContext()
  const projectItems = (projectsSectionData.projectItemsNext?.edges ?? [])
    .flatMap(edge => (edge?.node ? edge?.node : []))
    .filter(projectItem => projectItem.project.closed !== true)

  const closedProjectItems = (projectsSectionData.projectItemsNext?.edges ?? [])
    .flatMap(edge => (edge?.node ? edge?.node : []))
    .filter(projectItem => projectItem.project.closed === true)

  const [showClosedProjects, setShowClosedProjects] = useState(false)

  const {viewerCanUpdateMetadata, viewerCanUpdate, repository} = projectsSectionData

  // This can be consolidated once viewerCanUpdateMetadata is implemented in the pull_request model
  const readonly = !(viewerCanUpdateMetadata || viewerCanUpdate) || repository?.isArchived

  const issueId = projectsSectionData.id || ''
  const hasProjectItems = projectItems.length > 0 || closedProjectItems.length > 0

  const connectionId = ConnectionHandler.getConnectionID(
    issueId, // passed as input to the mutation/subscription
    'ProjectSection_projectItemsNext',
    {
      allowedOwner: allowedProjectOwner,
    },
  )

  const environment = useRelayEnvironment()
  const saveProjects = useCallback(
    (selectedProjects: Project[]) => {
      const projectsToAdd = selectedProjects.filter(project => !projectItems.some(p => p.project.id === project.id))

      const projectsToRemove = projectItems.filter(project => !selectedProjects.some(p => p.id === project.project.id))

      let hasError = false
      for (const project of projectsToAdd) {
        commitUpdateIssueProjectsMutation({
          environment,
          connectionId,
          projectId: project.id,
          issueId,
          onError: () => (hasError = true),
          onCompleted: onIssueUpdate,
        })
      }

      for (const project of projectsToRemove) {
        commitDeleteIssueProjectsMutation({
          environment,
          connectionId,
          projectId: project.project.id,
          itemId: project.id,
          onError: () => (hasError = true),
          onCompleted: onIssueUpdate,
        })
      }

      if (hasError) {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: ERRORS.couldNotUpdateProjects,
        })
      }
    },
    [addToast, connectionId, environment, issueId, onIssueUpdate, projectItems],
  )

  const selectedProjects = useMemo(
    () =>
      projectItems.map(projectItem =>
        // eslint-disable-next-line no-restricted-syntax
        readInlineData<ProjectPickerProject$key>(ProjectPickerProjectFragment, projectItem.project),
      ),
    [projectItems],
  )

  const totalClosedProjects = closedProjectItems.length

  const sectionHeader = useMemo(() => {
    if (!projectsSectionData.repository || readonly) return <ReadonlyProjectsSectionHeader />

    return (
      <ProjectPicker
        pickerId={`edit-issue-projects-picker-${issueId}`}
        repo={projectsSectionData.repository.name}
        owner={projectsSectionData.repository.owner.login}
        selectedProjects={selectedProjects}
        readonly={readonly}
        firstSelectedProjectTitle={projectItems.length > 0 ? projectItems[0]!.project.title : ''}
        onSave={saveProjects}
        anchorElement={props => <ProjectsSectionHeader {...props} />}
        insidePortal={insideSidePanel}
      />
    )
  }, [issueId, projectItems, projectsSectionData.repository, readonly, saveProjects, selectedProjects, insideSidePanel])

  if (!projectsSectionData.repository || !projectsSectionData.number) return null

  return (
    <ProjectsSection sectionHeader={sectionHeader} hasItems={hasProjectItems}>
      <Box sx={{pl: 2, pr: 1, width: '100%'}}>
        {projectItems.map(projectItem => (
          <ProjectItemSection
            key={projectItem.id}
            onIssueUpdate={onIssueUpdate}
            projectItem={projectItem}
            isOpen={selectedProjectId === projectItem.project.id}
          />
        ))}
        {totalClosedProjects > 0 && (
          <>
            <Button
              variant={'invisible'}
              trailingVisual={showClosedProjects ? ChevronUpIcon : ChevronDownIcon}
              sx={{
                color: 'fg.subtle',
                p: 0,
                fontSize: 0,
                '&:hover:not([disabled])': {background: 'transparent'},
              }}
              onClick={() => setShowClosedProjects(!showClosedProjects)}
              aria-label={LABELS.showClosedProjects}
            >
              {`${totalClosedProjects} closed project${totalClosedProjects > 1 ? 's' : ''}`}
            </Button>
            {showClosedProjects &&
              closedProjectItems.map(projectItem => (
                <ProjectItemSection
                  key={projectItem.id}
                  onIssueUpdate={onIssueUpdate}
                  projectItem={projectItem}
                  isOpen={selectedProjectId === projectItem.project.id}
                />
              ))}
          </>
        )}
      </Box>
    </ProjectsSection>
  )
}
