import {LabelFragment, LabelPicker} from '@github-ui/item-picker/LabelPicker'
import type {LabelPickerLabel$data, LabelPickerLabel$key} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import {useCallback, useEffect, useMemo, useState} from 'react'
import {readInlineData} from 'react-relay'
import {graphql, useFragment, usePaginationFragment, useRelayEnvironment} from 'react-relay/hooks'

import {isFeatureEnabled} from '@github-ui/feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ERRORS} from '@github-ui/item-picker/Errors'
import {commitSetLabelsForLabelableMutation} from '@github-ui/item-picker/commitSetLabelsForLabelableMutation'
import {LabelsList as Labels, type Label} from '@github-ui/labels-list'
import type {SxProp} from '@primer/react'
import {LABELS} from '../../constants/labels'
import {TEST_IDS} from '../../constants/test-ids'
import {ReadonlySectionHeader} from '../ReadonlySectionHeader'
import {Section} from '../Section'
import {SectionHeader} from '../SectionHeader'
import type {LabelsSectionAssignedLabels$key} from './__generated__/LabelsSectionAssignedLabels.graphql'
import type {LabelsSectionAssignedLabelsQuery} from './__generated__/LabelsSectionAssignedLabelsQuery.graphql'
import type {LabelsSectionFragment$key} from './__generated__/LabelsSectionFragment.graphql'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useCopilot} from '../../utils/useCopilot'
import {CopilotLabelsSection} from './CopilotLabelsSection'
import {userRejectedCopilotLabelsSuggestion} from '../../utils/copilot-utils'

const ReadonlyLabelsSectionHeader = () => <ReadonlySectionHeader title={LABELS.sectionTitles.labels} />

type LabelsSectionProps = {
  sectionHeader: JSX.Element
  labels: Label[]
} & SxProp
const LabelsSection = ({sectionHeader, labels}: LabelsSectionProps) => {
  return (
    <Section sectionHeader={sectionHeader} emptyText={labels.length > 0 ? undefined : LABELS.emptySections.labels}>
      <Labels labels={labels} testId={TEST_IDS.issueLabels} />
    </Section>
  )
}

type CreateIssueLabelsSectionProps = {
  repo: string
  owner: string
  readonly: boolean
  labels: LabelPickerLabel$data[]
  onSelectionChange: (labels: LabelPickerLabel$data[]) => void
  shortcutEnabled: boolean
}
export const CreateIssueLabelsSection = ({
  repo,
  owner,
  readonly,
  labels,
  onSelectionChange,
  ...sharedConfigProps
}: CreateIssueLabelsSectionProps) => {
  const sectionHeader = readonly ? (
    <ReadonlyLabelsSectionHeader />
  ) : (
    <LabelPicker
      repo={repo}
      owner={owner}
      readonly={readonly}
      labels={labels}
      onSelectionChanged={onSelectionChange}
      showNoMatchItem
      anchorElement={(anchorProps, ref) => (
        <SectionHeader title={LABELS.sectionTitles.labels} buttonProps={anchorProps} ref={ref} />
      )}
      {...sharedConfigProps}
    />
  )
  return <LabelsSection sectionHeader={sectionHeader} labels={labels} />
}

export const labelsSectionFragment = graphql`
  fragment LabelsSectionFragment on Issue {
    id
    title
    body
    repository {
      name
      owner {
        login
      }
      isArchived
    }
    ...LabelsSectionAssignedLabels
    viewerCanLabel
  }
`

export const LabelsSectionAssignedLabelsFragment = graphql`
  fragment LabelsSectionAssignedLabels on Labelable
  @argumentDefinitions(cursor: {type: "String"}, assignedLabelPageSize: {type: "Int", defaultValue: 100})
  @refetchable(queryName: "LabelsSectionAssignedLabelsQuery") {
    labels(first: $assignedLabelPageSize, after: $cursor, orderBy: {field: NAME, direction: ASC})
      @connection(key: "MetadataSectionAssignedLabels_labels") {
      edges {
        node {
          # eslint-disable-next-line relay/must-colocate-fragment-spreads
          ...LabelPickerLabel
        }
      }
    }
  }
`

export type EditIssueLabelsSectionProps = {
  onIssueUpdate?: () => void
  singleKeyShortcutsEnabled: boolean
  issue: LabelsSectionFragment$key
  insideSidePanel?: boolean
}

export function EditIssueLabelsSection({
  issue,
  onIssueUpdate,
  singleKeyShortcutsEnabled,
  insideSidePanel,
}: EditIssueLabelsSectionProps) {
  const data = useFragment(labelsSectionFragment, issue)
  const {
    repository: {
      owner: {login: owner},
      name: repo,
      isArchived: isRepositoryArchived,
    },
  } = data

  const {data: labelDataRaw} = usePaginationFragment<LabelsSectionAssignedLabelsQuery, LabelsSectionAssignedLabels$key>(
    LabelsSectionAssignedLabelsFragment,
    data,
  )

  const labelData = labelDataRaw

  const {id: issueId, viewerCanLabel} = data

  const labels = useMemo(
    () =>
      labelData.labels?.edges?.flatMap(e =>
        // eslint-disable-next-line no-restricted-syntax
        e?.node ? [readInlineData<LabelPickerLabel$key>(LabelFragment, e?.node)] : [],
      ) || [],
    [labelData],
  )

  const {getSuggestions, suggestedLabels, labelsStatus} = useCopilot()
  const environment = useRelayEnvironment()
  const copilot_auto_assign_metadata = isFeatureEnabled('copilot_auto_assign_metadata')

  // only show the copilot component if
  // 1. feature flag is enabled,
  // 2. the user can label the issue, AND
  // 3. there are no labels on the issue
  const [shouldShowCopilotComponent, setShouldShowCopilotComponent] = useState(
    copilot_auto_assign_metadata &&
      viewerCanLabel &&
      labels.length === 0 &&
      !userRejectedCopilotLabelsSuggestion(issueId),
  )

  useEffect(() => {
    if (shouldShowCopilotComponent) {
      getSuggestions({
        issueId,
        environment,
        issueTitle: data.title,
        issueBody: data.body,
        repositoryName: repo,
        repositoryOwner: owner,
        type: 'labels',
      })
    }
  }, [shouldShowCopilotComponent, issueId, environment, data.title, data.body, repo, owner, getSuggestions])

  const readonlyLabel = !viewerCanLabel || isRepositoryArchived

  const {addToast} = useToastContext()

  const onSelectionChanged = useCallback(
    (selectedLabels: LabelPickerLabel$data[]) => {
      if (shouldShowCopilotComponent && selectedLabels.length > 0) {
        setShouldShowCopilotComponent(false)
        sendEvent('copilot_suggested_labels.skipped', {issueId})
      }

      if (shouldShowCopilotComponent && selectedLabels.length === 0) {
        setShouldShowCopilotComponent(true)
      }

      commitSetLabelsForLabelableMutation({
        environment,
        input: {labelableId: issueId, labels: selectedLabels, labelableTypeName: 'Issue'},
        onError: () =>
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: ERRORS.couldNotUpdateLabels,
          }),
        onCompleted: onIssueUpdate,
      })
    },
    [addToast, environment, issueId, onIssueUpdate, shouldShowCopilotComponent],
  )

  const onConfirmCopilotLabels = useCallback(
    (selectedSuggestions: LabelPickerLabel$data[]) => {
      onSelectionChanged(selectedSuggestions)
      setShouldShowCopilotComponent(false)
      sendEvent('copilot_suggested_labels.confirm', {
        pickedLabels: selectedSuggestions.map(label => label.name).join(','),
        suggestedLabels: suggestedLabels.map(label => label.name).join(','),
        pickedCount: selectedSuggestions.length,
        suggestedCount: suggestedLabels.length,
        issueId,
      })
    },
    [suggestedLabels, issueId, onSelectionChanged],
  )

  const onErrorRetryCopilotLabels = useCallback(() => {
    getSuggestions({
      issueId,
      environment,
      issueTitle: data.title,
      issueBody: data.body,
      repositoryName: repo,
      repositoryOwner: owner,
      type: 'labels',
    })
    sendEvent('copilot_suggested_labels_error.retry', {issueId})
  }, [getSuggestions, issueId, environment, data.title, data.body, repo, owner])

  const labelSectionHeader = useMemo(() => {
    if (readonlyLabel) {
      return <ReadonlyLabelsSectionHeader />
    }

    return (
      <LabelPicker
        repo={repo}
        owner={owner}
        readonly={readonlyLabel}
        shortcutEnabled={singleKeyShortcutsEnabled}
        labels={labels}
        copilotSuggestedLabels={suggestedLabels}
        onSelectionChanged={onSelectionChanged}
        anchorElement={(anchorProps, ref) => (
          <SectionHeader title={LABELS.sectionTitles.labels} buttonProps={anchorProps} ref={ref} />
        )}
        insidePortal={insideSidePanel}
        showNoMatchItem
      />
    )
  }, [
    readonlyLabel,
    repo,
    owner,
    singleKeyShortcutsEnabled,
    labels,
    suggestedLabels,
    onSelectionChanged,
    insideSidePanel,
  ])

  if (!shouldShowCopilotComponent) {
    return <LabelsSection sectionHeader={labelSectionHeader} labels={labels} />
  } else {
    return (
      <CopilotLabelsSection
        issueBody={data.body}
        issueId={issueId}
        issueTitle={data.title}
        repositoryName={repo}
        repositoryOwner={owner}
        sectionHeader={labelSectionHeader}
        setShouldShowCopilotComponent={setShouldShowCopilotComponent}
        suggestedLabels={suggestedLabels}
        labelsStatus={labelsStatus}
        onConfirmLabels={onConfirmCopilotLabels}
        onErrorRetry={onErrorRetryCopilotLabels}
      />
    )
  }
}
