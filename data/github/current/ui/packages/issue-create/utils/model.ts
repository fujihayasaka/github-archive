import type {createIssueMutation} from '../mutations/__generated__/createIssueMutation.graphql'
import type {useHandleTemplateChangeIssueForm$data} from '../__generated__/useHandleTemplateChangeIssueForm.graphql'
import type {useHandleTemplateChangeIssueTemplate$data} from '../__generated__/useHandleTemplateChangeIssueTemplate.graphql'

type CreatedIssue = Exclude<
  Exclude<createIssueMutation['response']['createIssue'], null | undefined>['issue'],
  null | undefined
>

export type OnCreateProps = {
  issue: CreatedIssue
  createMore: boolean
}

type IssueFormData = NonNullable<useHandleTemplateChangeIssueForm$data>
type IssueTemplateData = NonNullable<useHandleTemplateChangeIssueTemplate$data>
export type FetchedIssueCreatePayload = {
  name: string
  fileName: string
  kind: IssueCreationKind
  data: IssueFormData | IssueTemplateData | BlankIssueData
}

type BlankIssueData = {
  __typename: 'BlankIssue'
  __id: 'BLANK_ISSUE'
  title: ''
  body: ''
  assignees: {
    edges: []
  }
  labels: {
    edges: []
  }
}
export type IssueCreationData = BlankIssueData | IssueFormData | IssueTemplateData

export type IssueCreatePayload = {
  name: string
  fileName: string
  kind: IssueCreationKind
  data: IssueCreationData
}

export const BLANK_ISSUE = 'Blank issue'
export const BLANK_ISSUE_ID = 'BLANK_ISSUE'

export function instanceOfIssueFormData(data: IssueCreationData): data is IssueFormData {
  return data.__typename === 'IssueForm'
}

export function instanceOfIssueTemplateData(data: IssueCreationData): data is IssueTemplateData {
  return data.__typename === 'IssueTemplate'
}

export function instanceOfBlankIssueData(data: IssueCreationData): data is BlankIssueData {
  return data.__typename === 'BlankIssue'
}

export const IssueCreationKind = {
  IssueForm: 'IssueForm',
  IssueTemplate: 'IssueTemplate',
  ContactLink: 'ContactLink',
  BlankIssue: 'BlankIssue',
} as const

export type IssueCreationKind = (typeof IssueCreationKind)[keyof typeof IssueCreationKind]

const blankIssue: IssueCreatePayload = {
  name: BLANK_ISSUE,
  fileName: BLANK_ISSUE_ID,
  kind: IssueCreationKind.BlankIssue,
  data: {
    __typename: 'BlankIssue',
    __id: BLANK_ISSUE_ID,
    title: '',
    body: '',
    assignees: {
      edges: [],
    },
    labels: {
      edges: [],
    },
  },
}

export function getBlankIssue(): FetchedIssueCreatePayload {
  return blankIssue as FetchedIssueCreatePayload
}
