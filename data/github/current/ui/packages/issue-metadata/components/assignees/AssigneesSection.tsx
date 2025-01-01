import {Assignees} from '@github-ui/assignees'
import {ERRORS} from '@github-ui/item-picker/Errors'

import {commitUpdateIssueAssigneesMutation} from '@github-ui/item-picker/commitUpdateIssueAssigneesMutation'
import type {Assignee} from '@github-ui/item-picker/AssigneePicker'
import {AssigneeFragment, AssigneePicker, AssigneeRepositoryPicker} from '@github-ui/item-picker/AssigneePicker'
import {useViewer} from '@github-ui/item-picker/useViewer'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useMemo, useCallback, type RefObject} from 'react'
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
import type {AssigneePickerAssignee$key} from '@github-ui/item-picker/AssigneePicker.graphql'

const ReadonlyAssigneesSectionHeader = () => <ReadonlySectionHeader title={LABELS.sectionTitles.assignees} />

const AssigneesSectionLazyFragment = graphql`
  fragment AssigneesSectionLazyFragment on Issue {
    suggestedActors(first: 10) {
      nodes {
        ...AssigneePickerAssignee @dangerously_unaliased_fixme
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

  const pickerProps = {
    repo,
    owner,
    readonly,
    includeAuthorableBots: false,
    includeAssignableBots: true,
    assigneeTokens: [],
    assignees,
    onSelectionChange,
    anchorElement: (anchorProps: React.HTMLAttributes<HTMLElement>, ref: RefObject<HTMLButtonElement>) => (
      <SectionHeader title={LABELS.sectionTitles.assignees} buttonProps={anchorProps} ref={ref} />
    ),
    maximumAssignees,
    ...sharedConfigProps,
  }

  const sectionHeader = readonly ? <ReadonlyAssigneesSectionHeader /> : <AssigneeRepositoryPicker {...pickerProps} />

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
    assignedActors(first: 20) {
      nodes {
        ...AssigneePickerAssignee @dangerously_unaliased_fixme
      }
    }
  }
`

export const assigneesSectionFragment = graphql`
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

  const suggestions = useMemo(() => {
    return (lazyData?.suggestedActors?.nodes || []).flatMap(actor =>
      actor
        ? // eslint-disable-next-line no-restricted-syntax
          [readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, actor)]
        : [],
    )
  }, [lazyData?.suggestedActors?.nodes])

  const assignees = useMemo(() => {
    return (assigneesData.assignedActors?.nodes || []).flatMap(actor =>
      // eslint-disable-next-line no-restricted-syntax
      actor ? [readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, actor)] : [],
    )
  }, [assigneesData.assignedActors?.nodes])

  const {addToast} = useToastContext()
  const environment = useRelayEnvironment()

  const updateAssignees = useCallback(
    (selectedAssignees: Assignee[]) => {
      commitUpdateIssueAssigneesMutation({
        environment,
        input: {issueId, assignedActors: selectedAssignees, participants: suggestions},
        onError: () =>
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: ERRORS.couldNotUpdateAssignees,
          }),
        onCompleted: onIssueUpdate,
      })
    },
    [addToast, environment, issueId, onIssueUpdate, suggestions],
  )

  const readonlyAssignee = !viewerCanAssign || isRepositoryArchived

  const assigneeSectionHeader = useMemo(() => {
    if (readonlyAssignee) {
      return <ReadonlyAssigneesSectionHeader />
    }

    const pickerProps = {
      repo,
      owner,
      number,
      anchorElement: (props: React.HTMLAttributes<HTMLElement>, ref: RefObject<HTMLButtonElement>) => (
        <SectionHeader title={LABELS.sectionTitles.assignees} buttonProps={props} ref={ref} />
      ),
      readonly: readonlyAssignee,
      shortcutEnabled: singleKeyShortcutsEnabled,
      assignees,
      onSelectionChange: (selectedAssignees: Assignee[]) => updateAssignees(selectedAssignees),
      maximumAssignees,
      insidePortal: insideSidePanel,
      suggestions,
    }

    return <AssigneePicker {...pickerProps} />
  }, [
    readonlyAssignee,
    repo,
    owner,
    number,
    singleKeyShortcutsEnabled,
    assignees,
    suggestions,
    maximumAssignees,
    insideSidePanel,
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
