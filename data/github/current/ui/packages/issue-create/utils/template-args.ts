import {URLS} from '../constants/urls'
import {BLANK_ISSUE} from './model'
import {safeStringArrayParamSet, safeStringParamGet, safeStringParamSet} from './urls'
import type {MilestonePickerMilestone$data} from '@github-ui/item-picker/MilestonePickerMilestone.graphql'
import type {ProjectPickerProject$data as Project} from '@github-ui/item-picker/ProjectPickerProject.graphql'
import type {LabelPickerLabel$data} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import type {IssueTypePickerIssueType$data} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'
import type {Assignee} from '@github-ui/item-picker/AssigneePicker'
import type {IssueCreateInitialValuesState} from '../contexts/IssueCreateInitialValuesContext'

export type IssueCreateArguments = {
  repository?: {
    owner: string
    name: string
  }
  templateFileName?: string
  initialValues?: IssueCreateValueTypes
  parentIssue?: {
    id: string
  }
}

export type IssueCreateDiscussionData = {
  title: string
  formattedBody: string
  labels?: LabelPickerLabel$data[]
}

export type IssueCreateValueTypes = {
  title?: string
  appendTitleToTemplate?: string
  body?: string
} & IssueCreateMetadataTypes

export type IssueCreateMetadataTypes = {
  assignees?: Assignee[]
  labels?: LabelPickerLabel$data[]
  milestone?: MilestonePickerMilestone$data
  projects?: Project[]
  type?: IssueTypePickerIssueType$data
  discussion?: IssueCreateDiscussionData
}

export type ConstructIssueCreateParamsType = {
  repository: {owner: {login: string}; name: string} | undefined
  templateFileName?: string | undefined
} & IssueCreateValueTypes

export function hasAnyInitialValues(initialValues?: IssueCreateValueTypes) {
  if (!initialValues) {
    return false
  }

  return (
    initialValues.title !== undefined ||
    initialValues.body !== undefined ||
    initialValues.assignees !== undefined ||
    initialValues.labels !== undefined ||
    initialValues.milestone !== undefined ||
    initialValues.projects !== undefined ||
    initialValues.type !== undefined
  )
}

export function constructIssueCreateParams({
  includeRepository,
  repository,
  templateFileName,
  title,
  body,
  assignees,
  labels,
  projects,
  milestone,
  type,
}: ConstructIssueCreateParamsType & {includeRepository: boolean}): string {
  const searchParams = new URLSearchParams(ssrSafeWindow?.location?.search || '')

  if (includeRepository && repository) {
    searchParams.set(URLS.queryParams.org, repository.owner.login)
    searchParams.set(URLS.queryParams.repo, repository.name)
  }

  if (templateFileName) {
    searchParams.set(URLS.queryParams.template, templateFileName)
  }

  safeStringParamSet(searchParams, URLS.queryParams.title, title, URLS.maxQueryLengthLimits.title)
  safeStringParamSet(searchParams, URLS.queryParams.body, body, URLS.maxQueryLengthLimits.body)

  if (assignees) {
    safeStringArrayParamSet(
      searchParams,
      URLS.queryParams.assignees,
      assignees ? assignees.map(a => a.login) : undefined,
      URLS.maxQueryLengthLimits.assignees,
    )
  }

  if (labels) {
    safeStringArrayParamSet(
      searchParams,
      URLS.queryParams.labels,
      labels.map(l => l.name),
      URLS.maxQueryLengthLimits.assignees,
    )
  }

  if (projects && repository?.owner) {
    safeStringArrayParamSet(
      searchParams,
      URLS.queryParams.projects,
      projects.map(p => `${repository.owner.login}/${p.number}`),
      URLS.maxQueryLengthLimits.assignees,
    )
  }

  if (milestone) {
    searchParams.set(URLS.queryParams.milestone, milestone.title)
  }

  if (type) {
    searchParams.set(URLS.queryParams.type, type.name)
  }

  return searchParams.toString()
}

export function getIssueCreateArguments(
  searchParams: URLSearchParams,
  initialMetadata?: IssueCreateMetadataTypes,
  initialContextValues?: IssueCreateInitialValuesState,
) {
  const org = searchParams.get(URLS.queryParams.org) || initialContextValues?.owner || null
  const repo = searchParams.get(URLS.queryParams.repo) || initialContextValues?.repository || null
  const template = searchParams.get(URLS.queryParams.template) || initialContextValues?.template || null

  let issueCreateArguments: IssueCreateArguments = {
    ...(org !== null &&
      repo !== null && {
        repository: {
          owner: org,
          name: repo,
        },
      }),
    ...(template !== null && {templateFileName: template}),
  }

  const title =
    safeStringParamGet(searchParams, URLS.queryParams.title, URLS.maxQueryLengthLimits.title) ||
    initialContextValues?.title
  let body = safeStringParamGet(searchParams, URLS.queryParams.permalink, URLS.maxQueryLengthLimits.body)
  if (body === undefined) {
    body =
      safeStringParamGet(searchParams, URLS.queryParams.body, URLS.maxQueryLengthLimits.body) ||
      initialContextValues?.body
  } else {
    body = decodeURIComponent(body)
  }

  const templateArguments: IssueCreateValueTypes = {
    ...(title !== undefined && {title}),
    ...(body !== undefined && {body}),
    ...initialMetadata,
  }

  if (Object.keys(issueCreateArguments).length === 0) {
    // Special case, in the old experience, which relies on repo scope, blank issues don't set a template variable, so we need to check this.
    // In this experience, it means we won't have an org, or repo, since we're repo scoped, but we need to see if there are other valid params.
    if (Object.keys(templateArguments).length > 0) {
      issueCreateArguments = {
        templateFileName: BLANK_ISSUE,
      }
    } else {
      return undefined
    }
  }

  return {
    ...issueCreateArguments,
    ...(Object.keys(templateArguments).length > 0 && {initialValues: templateArguments}),
  }
}
