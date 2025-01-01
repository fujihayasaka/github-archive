import {Assignees} from '@github-ui/assignees'
import {ERRORS} from '@github-ui/item-picker/Errors'
import type {AssigneePickerAssignee$key} from '@github-ui/item-picker/AssigneePicker.graphql'

import {commitUpdateIssueAssigneesMutation} from '@github-ui/item-picker/updateIssueAssigneesMutation'
import {commitAssignAppToIssueMutation} from '@github-ui/item-picker/commitAssignAppToIssueMutation'
import type {Assignee} from '@github-ui/item-picker/AssigneePicker'
import {
  AssigneeFragment,
  AssigneePicker,
  AssigneeRepositoryPicker,
  useViewer,
} from '@github-ui/item-picker/AssigneePicker'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useMemo, useCallback} from 'react'
import {readInlineData, useRelayEnvironment} from 'react-relay'
import {graphql, useFragment} from 'react-relay/hooks'

import {LABELS} from '../../constants/labels'
import {ReadonlySectionHeader} from '../ReadonlySectionHeader'
import {SectionHeader} from '../SectionHeader'
import {Section} from '../Section'
import {Button, type SxProp} from '@primer/react'
import type {AssigneesSectionFragment$key} from './__generated__/AssigneesSectionFragment.graphql'
import type {AssigneesSectionAssignees$key} from './__generated__/AssigneesSectionAssignees.graphql'
import {TEST_IDS} from '../../constants/test-ids'
import type {AssigneesSectionLazyFragment$key} from './__generated__/AssigneesSectionLazyFragment.graphql'
import {noop} from '@github-ui/noop'
import {isCopilot} from '@github-ui/assignees/copilot-user'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

const ReadonlyAssigneesSectionHeader = () => <ReadonlySectionHeader title={LABELS.sectionTitles.assignees} />

export const AssigneesSectionLazyFragment = graphql`
  fragment AssigneesSectionLazyFragment on Issue {
    participants(first: 10) {
      nodes {
        ...AssigneePickerAssignee
      }
    }
    repository {
      installedAppInstallations(isAssignable: true, first: 10) {
        edges {
          node {
            app {
              id
              # eslint-disable-next-line relay/unused-fields
              slug
              name
            }
          }
        }
      }
    }
  }
`

type AssigneesSectionProps = {
  sectionHeader: JSX.Element
  onSelfAssignClick: () => void
  assignees: Assignee[]
  readonly: boolean
} & SxProp
const AssigneesSection = ({sectionHeader, onSelfAssignClick, assignees, readonly}: AssigneesSectionProps) => {
  const emptyHeader = !readonly ? (
    <>
      {LABELS.emptySections.assignees(true)}
      <Button
        variant="link"
        onClick={onSelfAssignClick}
        sx={{color: 'fg.accent', fontWeight: 400, cursor: 'pointer', '&:hover': {textDecoration: 'none'}}}
      >
        {LABELS.emptySections.selfAssign}
      </Button>
    </>
  ) : (
    LABELS.emptySections.assignees(false)
  )

  return (
    <Section sectionHeader={sectionHeader} emptyText={assignees.length > 0 ? undefined : emptyHeader}>
      <Assignees assignees={assignees} testId={TEST_IDS.assignees} />
    </Section>
  )
}

export type CreateIssueAssigneesSectionProps = {
  repo: string
  owner: string
  readonly: boolean
  assignees: Assignee[]
  maximumAssignees?: number
  onSelectionChange: (value: Assignee[]) => void
  insidePortal: boolean
  shortcutEnabled: boolean
} & SxProp
export function CreateIssueAssigneesSection({
  repo,
  owner,
  readonly,
  assignees,
  onSelectionChange,
  maximumAssignees,
  sx,
  ...sharedConfigProps
}: CreateIssueAssigneesSectionProps) {
  const viewer = useViewer()

  const sectionHeader = readonly ? (
    <ReadonlyAssigneesSectionHeader />
  ) : (
    <AssigneeRepositoryPicker
      repo={repo}
      owner={owner}
      readonly={readonly}
      assigneeTokens={[]}
      assignees={assignees}
      onSelectionChange={onSelectionChange}
      anchorElement={(anchorProps, ref) => (
        <SectionHeader title={LABELS.sectionTitles.assignees} buttonProps={anchorProps} ref={ref} />
      )}
      maximumAssignees={maximumAssignees}
      {...sharedConfigProps}
    />
  )

  return (
    <AssigneesSection
      sectionHeader={sectionHeader}
      onSelfAssignClick={() => onSelectionChange(viewer ? [viewer] : [])}
      assignees={assignees}
      readonly={readonly}
      sx={sx}
    />
  )
}

export const assigneesSectionAssignees = graphql`
  fragment AssigneesSectionAssignees on Issue {
    assignees(first: 20) {
      nodes {
        ...AssigneePickerAssignee
      }
    }
  }
`

const assigneesSectionFragment = graphql`
  fragment AssigneesSectionFragment on Issue {
    id
    number
    repository {
      name
      owner {
        login
      }
      isArchived
      planFeatures {
        maximumAssignees
      }
    }
    ...AssigneesSectionAssignees
    # eslint-disable-next-line relay/unused-fields
    viewerCanUpdateNext
    viewerCanAssign
  }
`

export type EditIssueAssigneesSectionProps = {
  issue: AssigneesSectionFragment$key
  viewer: AssigneePickerAssignee$key | null
  lazyKey?: AssigneesSectionLazyFragment$key
  onIssueUpdate?: () => void
  singleKeyShortcutsEnabled: boolean
  insideSidePanel?: boolean
}
export function EditIssueAssigneesSection({
  issue,
  viewer,
  lazyKey,
  onIssueUpdate,
  singleKeyShortcutsEnabled,
  insideSidePanel,
}: EditIssueAssigneesSectionProps) {
  const data = useFragment(assigneesSectionFragment, issue)
  const {
    repository: {
      owner: {login: owner},
      name: repo,
      isArchived: isRepositoryArchived,
      planFeatures,
    },
    number,
  } = data

  const maximumAssignees = planFeatures?.maximumAssignees || 10

  const assigneesData = useFragment<AssigneesSectionAssignees$key>(assigneesSectionAssignees, data)
  // eslint-disable-next-line no-restricted-syntax
  const viewerData = readInlineData(AssigneeFragment, viewer)

  const {id: issueId, viewerCanAssign} = data

  const lazyData = useFragment(AssigneesSectionLazyFragment, lazyKey)

  const participants = (lazyData?.participants?.nodes || []).flatMap(participant =>
    participant
      ? // eslint-disable-next-line no-restricted-syntax
        [readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, participant)]
      : [],
  )

  const assignableApps = (lazyData?.repository?.installedAppInstallations?.edges || []).flatMap(edge =>
    edge?.node?.app ? [edge.node.app] : [],
  )

  const assignees = useMemo(() => {
    return (assigneesData.assignees?.nodes || []).flatMap(assignee =>
      // eslint-disable-next-line no-restricted-syntax
      assignee ? [readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, assignee)] : [],
    )
  }, [assigneesData])

  const {addToast} = useToastContext()
  const environment = useRelayEnvironment()
  const copilot_swe_agent = useFeatureFlag('copilot_swe_agent')

  const updateAssignees = useCallback(
    (selectedAssignees: Assignee[]) => {
      const copilotAssignees = selectedAssignees.filter(a => isCopilot(a.login))
      if (copilot_swe_agent && copilotAssignees.length !== 0) {
        commitAssignAppToIssueMutation({
          environment,
          input: {
            issueId,
            appIds: copilotAssignees.map(a => a.id),
          },
          onError: () =>
            // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
            addToast({
              type: 'error',
              message: ERRORS.couldNotUpdateAssignees,
            }),
          onCompleted: onIssueUpdate,
        })
      } else {
        commitUpdateIssueAssigneesMutation({
          environment,
          input: {issueId, assignees: selectedAssignees, participants},
          onError: () =>
            // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
            addToast({
              type: 'error',
              message: ERRORS.couldNotUpdateAssignees,
            }),
          onCompleted: onIssueUpdate,
        })
      }
    },
    [addToast, environment, issueId, onIssueUpdate, participants],
  )

  const readonlyAssignee = !viewerCanAssign || isRepositoryArchived

  const assigneeSectionHeader = useMemo(() => {
    if (readonlyAssignee) {
      return <ReadonlyAssigneesSectionHeader />
    }

    return (
      <AssigneePicker
        repo={repo}
        owner={owner}
        number={number}
        anchorElement={(anchorProps, ref) => (
          <SectionHeader title={LABELS.sectionTitles.assignees} buttonProps={anchorProps} ref={ref} />
        )}
        readonly={readonlyAssignee}
        shortcutEnabled={singleKeyShortcutsEnabled}
        assignees={assignees}
        suggestions={participants}
        onSelectionChange={(selectedAssignees: Assignee[]) => updateAssignees(selectedAssignees)}
        maximumAssignees={maximumAssignees}
        insidePortal={insideSidePanel}
        assignableApps={assignableApps}
      />
    )
  }, [
    readonlyAssignee,
    repo,
    owner,
    number,
    singleKeyShortcutsEnabled,
    assignees,
    participants,
    maximumAssignees,
    insideSidePanel,
    assignableApps,
    updateAssignees,
  ])

  return (
    <AssigneesSection
      sectionHeader={assigneeSectionHeader}
      assignees={assignees}
      onSelfAssignClick={() => (viewerData ? updateAssignees([viewerData]) : noop)}
      readonly={readonlyAssignee}
    />
  )
}
