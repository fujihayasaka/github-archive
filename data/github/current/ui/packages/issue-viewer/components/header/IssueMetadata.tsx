import {useMemo, type ReactElement} from 'react'
import styles from './IssueMetadata.module.css'
import {LabelsList} from '@github-ui/labels-list'
import type {AssigneePickerAssignee$key} from '@github-ui/item-picker/AssigneePicker.graphql'
import type {LabelPickerLabel$key} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import type {MilestonePickerMilestone$key} from '@github-ui/item-picker/MilestonePickerMilestone.graphql'
import {MilestoneMetadata} from './MilestoneMetadata'
import {graphql, readInlineData} from 'relay-runtime'
import type {IssueMetadata$key} from './__generated__/IssueMetadata.graphql'
import {useFragment} from 'react-relay'
import {AssigneeFragment} from '@github-ui/item-picker/AssigneePicker'
import {MilestoneFragment} from '@github-ui/item-picker/MilestonePicker'
import {AssigneesMetadata} from './AssigneesMetadata'
import {LabelFragment} from '@github-ui/item-picker/LabelPicker'
import {LabelsSectionAssignedLabelsFragment} from '@github-ui/issue-metadata/LabelsSection'
import type {LabelsSectionAssignedLabels$key} from '@github-ui/issue-metadata/LabelsSectionAssignedLabels.graphql'
import {assigneesSectionAssignees} from '@github-ui/issue-metadata/AssigneesSection'
import type {AssigneesSectionAssignees$key} from '@github-ui/issue-metadata/AssigneesSectionAssignees.graphql'
import {milestonesSectionMilestone} from '@github-ui/issue-metadata/MilestonesSection'
import type {MilestonesSectionMilestone$key} from '@github-ui/issue-metadata/MilestonesSectionMilestone.graphql'

/*
  This fragment fetches metadata for the issue header, including assignees, labels, and milestones.
  It is primarily used for mobile views but is not conditionally accessed due to similar fragments in the IssueSidebar within the IssueViewer.
  Relay optimizes data fetching by retrieving the data only once in such cases.
  If this component is used outside the IssueViewer, this fragment should be conditionally included for mobile screens only.
*/
const IssueMetadataFragment = graphql`
  fragment IssueMetadata on Issue {
    ...LabelsSectionAssignedLabels
    ...AssigneesSectionAssignees
    ...MilestonesSectionMilestone
  }
`

export const IssueMetadata = ({metadataKey}: {metadataKey: IssueMetadata$key}) => {
  const issueMetadata = useFragment(IssueMetadataFragment, metadataKey)
  const labelDataRaw = useFragment<LabelsSectionAssignedLabels$key>(LabelsSectionAssignedLabelsFragment, issueMetadata)
  const assigneesDataRaw = useFragment<AssigneesSectionAssignees$key>(assigneesSectionAssignees, issueMetadata)
  const milestoneDataRaw = useFragment<MilestonesSectionMilestone$key>(milestonesSectionMilestone, issueMetadata)

  const assigneesData = useMemo(() => {
    return (
      (assigneesDataRaw?.assignees?.nodes || []).flatMap(assignee => {
        // eslint-disable-next-line no-restricted-syntax
        return assignee ? [readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, assignee)] : []
      }) ?? []
    )
  }, [assigneesDataRaw?.assignees?.nodes])

  const labelsData = useMemo(() => {
    return (
      (labelDataRaw?.labels?.edges || []).flatMap(label => {
        // eslint-disable-next-line no-restricted-syntax
        return label?.node ? [readInlineData<LabelPickerLabel$key>(LabelFragment, label?.node)] : []
      }) ?? []
    )
  }, [labelDataRaw?.labels?.edges])

  const milestoneData = useMemo(() => {
    return milestoneDataRaw?.milestone
      ? // eslint-disable-next-line no-restricted-syntax
        readInlineData<MilestonePickerMilestone$key>(MilestoneFragment, milestoneDataRaw?.milestone)
      : null
  }, [milestoneDataRaw?.milestone])

  // return early if no data is available
  if (!assigneesData.length && !labelsData.length && !milestoneData) {
    return null
  }

  return (
    <div className={styles.issueMetadata}>
      {assigneesData?.length > 0 && (
        <Metadata title="Assignees">
          <AssigneesMetadata assignees={assigneesData} />
        </Metadata>
      )}
      {labelsData?.length > 0 && (
        <Metadata title="Labels">
          <LabelsList labels={labelsData} />
        </Metadata>
      )}
      {milestoneData && (
        <Metadata title="Milestone">
          <MilestoneMetadata milestone={milestoneData} />
        </Metadata>
      )}
    </div>
  )
}

const Metadata = ({title, children}: {title: string; children: ReactElement}) => (
  <div className={styles.metadata}>
    <div className={styles.metadataTitle}>{title}</div>
    <div className={styles.metadataValue}>{children}</div>
  </div>
)
