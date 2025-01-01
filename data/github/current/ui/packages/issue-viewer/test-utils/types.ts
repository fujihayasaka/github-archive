import type {AssigneePickerAssignee$data} from '@github-ui/item-picker/AssigneePicker.graphql'
import type {LabelPickerLabel$data} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import type {ProjectPickerProject$data} from '@github-ui/item-picker/ProjectPickerProject.graphql'
import type {IssueTypePickerIssueType$data} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'
import type {MilestonePickerMilestone$data} from '@github-ui/item-picker/MilestonePickerMilestone.graphql'

export type Assignee = Omit<AssigneePickerAssignee$data, ' $fragmentType'>

export type Label = Partial<Omit<LabelPickerLabel$data, ' $fragmentType'>>

export type Project = {
  project: Partial<Omit<ProjectPickerProject$data, ' $fragmentType'>>
}

export type IssueType = Partial<Omit<IssueTypePickerIssueType$data, ' $fragmentType'>>

export type Milestone = Partial<Omit<MilestonePickerMilestone$data, ' $fragmentType'>>

export type IssueMetadataFields = {
  assignees?: Assignee[]
  labels?: Label[]
  projects?: Project[]
  issueType?: IssueType
  milestone?: Milestone
}

export type MockRepository = Omit<RepositoryPickerRepository$data, ' $fragmentType'> &
  Omit<RepositoryPickerRepository$data, ' $fragmentType'> & {
    owner: {
      id: string
    }
  }
