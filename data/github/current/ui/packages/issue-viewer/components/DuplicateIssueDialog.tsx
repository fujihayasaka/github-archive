import {CreateIssueDialogEntryInternal} from '@github-ui/issue-create/CreateIssueDialogEntry'
import {Suspense, useMemo} from 'react'
import {readInlineData, useFragment} from 'react-relay'
import {useNavigate} from 'react-router-dom'
import type {OptionConfig} from './OptionConfig'
import {assigneesSectionAssignees, assigneesSectionFragment} from '@github-ui/issue-metadata/AssigneesSection'
import type {AssigneesSectionAssignees$key} from '@github-ui/issue-metadata/AssigneesSectionAssignees.graphql'
import type {AssigneePickerAssignee$key} from '@github-ui/item-picker/AssigneePicker.graphql'
import {AssigneeFragment} from '@github-ui/item-picker/AssigneePicker'
import {TypesSectionFragment, TypesSectionTypeFragment} from '@github-ui/issue-metadata/TypesSection'
import type {IssueTypePickerIssueType$key} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'
import {IssueTypeFragment} from '@github-ui/item-picker/IssueTypePicker'
import {LabelsSectionAssignedLabelsFragment, labelsSectionFragment} from '@github-ui/issue-metadata/LabelsSection'
import type {LabelsSectionAssignedLabels$key} from '@github-ui/issue-metadata/LabelsSectionAssignedLabels.graphql'
import type {LabelPickerLabel$key} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import {LabelFragment} from '@github-ui/item-picker/LabelPicker'
import {MilestonesSectionFragment, milestonesSectionMilestone} from '@github-ui/issue-metadata/MilestonesSection'
import type {MilestonesSectionMilestone$key} from '@github-ui/issue-metadata/MilestonesSectionMilestone.graphql'
import {MilestoneFragment} from '@github-ui/item-picker/MilestonePicker'
import type {MilestonePickerMilestone$key} from '@github-ui/item-picker/MilestonePickerMilestone.graphql'

import {projectSectionFragment} from '@github-ui/issue-metadata/ProjectsSection'
import {ProjectPickerProjectFragment} from '@github-ui/item-picker/ProjectPicker'
import type {ProjectPickerProject$key} from '@github-ui/item-picker/ProjectPickerProject.graphql'
import type {TypesSectionTypeFragment$key} from '@github-ui/issue-metadata/TypesSectionTypeFragment.graphql'
import type {ProjectsSectionFragment$key} from '@github-ui/issue-metadata/ProjectsSectionFragment.graphql'
import type {AssigneesSectionFragment$key} from '@github-ui/issue-metadata/AssigneesSectionFragment.graphql'
import type {LabelsSectionFragment$key} from '@github-ui/issue-metadata/LabelsSectionFragment.graphql'
import type {MilestonesSectionFragment$key} from '@github-ui/issue-metadata/MilestonesSectionFragment.graphql'
import type {TypesSectionFragment$key} from '@github-ui/issue-metadata/TypesSectionFragment.graphql'
import type {IssueSidebarPrimaryQuery$data} from './__generated__/IssueSidebarPrimaryQuery.graphql'

export type DuplicateIssueDialogProps = {
  showDuplicateIssueDialog: boolean
  setShowDuplicateIssueDialog: (value: boolean) => void
  optionConfig: OptionConfig
  repositoryOwner: string
  repositoryName: string
  title: string
  body: string
  issue: IssueSidebarPrimaryQuery$data
}

export const DuplicateIssueDialog = ({
  title,
  body,
  showDuplicateIssueDialog,
  setShowDuplicateIssueDialog,
  optionConfig,
  repositoryOwner,
  repositoryName,
  issue,
}: DuplicateIssueDialogProps) => {
  const navigate = useNavigate()
  const assigneesSection = useFragment<AssigneesSectionFragment$key>(assigneesSectionFragment, issue)
  const assigneesData = useFragment<AssigneesSectionAssignees$key>(assigneesSectionAssignees, assigneesSection)

  const typeSection = useFragment<TypesSectionFragment$key>(TypesSectionFragment, issue)
  const typeData = useFragment<TypesSectionTypeFragment$key>(TypesSectionTypeFragment, typeSection)

  const labelsSection = useFragment<LabelsSectionFragment$key>(labelsSectionFragment, issue)
  const labelsData = useFragment<LabelsSectionAssignedLabels$key>(LabelsSectionAssignedLabelsFragment, labelsSection)

  const milestoneSection = useFragment<MilestonesSectionFragment$key>(MilestonesSectionFragment, issue)
  const milestoneData = useFragment<MilestonesSectionMilestone$key>(milestonesSectionMilestone, milestoneSection)

  const projectsData = useFragment<ProjectsSectionFragment$key>(projectSectionFragment, issue)

  const assignees = useMemo(() => {
    return (assigneesData.assignedActors?.nodes || []).flatMap(assignee =>
      // eslint-disable-next-line no-restricted-syntax
      assignee ? [readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, assignee)] : [],
    )
  }, [assigneesData])

  const issueType = useMemo(() => {
    return typeData.issueType
      ? // eslint-disable-next-line no-restricted-syntax
        readInlineData<IssueTypePickerIssueType$key>(IssueTypeFragment, typeData.issueType)
      : undefined
  }, [typeData])

  const labels = useMemo(() => {
    return (labelsData.labels?.edges || []).flatMap(e =>
      // eslint-disable-next-line no-restricted-syntax
      e?.node ? [readInlineData<LabelPickerLabel$key>(LabelFragment, e?.node)] : [],
    )
  }, [labelsData])

  const milestone = useMemo(() => {
    return milestoneData.milestone
      ? // eslint-disable-next-line no-restricted-syntax
        readInlineData<MilestonePickerMilestone$key>(MilestoneFragment, milestoneData.milestone)
      : undefined
  }, [milestoneData])

  const projects = useMemo(() => {
    const projectItems = (projectsData.projectItemsNext?.edges ?? [])
      .flatMap(edge => (edge?.node ? edge?.node : []))
      .filter(projectItem => projectItem.project.closed !== true)

    return projectItems.map(projectItem =>
      // eslint-disable-next-line no-restricted-syntax
      readInlineData<ProjectPickerProject$key>(ProjectPickerProjectFragment, projectItem.project),
    )
  }, [projectsData])

  return (
    <Suspense>
      <CreateIssueDialogEntryInternal
        navigate={navigate}
        isCreateDialogOpen={showDuplicateIssueDialog}
        setIsCreateDialogOpen={setShowDuplicateIssueDialog}
        optionConfig={{
          ...optionConfig,
          showRepositoryPicker: false,
          defaultDisplayMode: 'IssueDuplication',
          issueCreateArguments: {
            repository: {
              owner: repositoryOwner,
              name: repositoryName,
            },
            initialValues: {
              title,
              body,
              assignees,
              type: issueType,
              labels,
              milestone,
              projects,
            },
          },
        }}
      />
    </Suspense>
  )
}
