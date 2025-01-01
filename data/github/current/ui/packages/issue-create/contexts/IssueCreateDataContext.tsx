import type React from 'react'
import {createContext, useCallback, useContext, useMemo, useState} from 'react'

import {clearSessionStorage, useSessionStorage} from '@github-ui/use-safe-storage/session-storage'
import type {RepositoryPickerRepository$data as Repository} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'

import type {
  LabelPickerLabel$data as Label,
  LabelPickerLabel$key,
} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import type {MilestonePickerMilestone$data as Milestone} from '@github-ui/item-picker/MilestonePickerMilestone.graphql'
import type {
  ProjectPickerProject$data as Project,
  ProjectPickerProject$key,
} from '@github-ui/item-picker/ProjectPickerProject.graphql'
import {storageKeys, storageMetadataKeys, storageTitleAndBodyKeys, VALUES} from '../constants/values'
import {IssueTypeFragment, type IssueType} from '@github-ui/item-picker/IssueTypePicker'
import {
  BLANK_ISSUE_ID,
  instanceOfIssueFormData,
  instanceOfIssueTemplateData,
  type IssueCreatePayload,
} from '../utils/model'
import type {SafeOptionConfig} from '../utils/option-config'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {AssigneeFragment, type Assignee} from '@github-ui/item-picker/AssigneePicker'
import {readInlineData} from 'relay-runtime'
import {LabelFragment} from '@github-ui/item-picker/LabelPicker'
import type {AssigneePickerAssignee$key} from '@github-ui/item-picker/AssigneePicker.graphql'
import {ProjectPickerProjectFragment} from '@github-ui/item-picker/ProjectPicker'
import type {IssueTypePickerIssueType$key} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'

// This is a placeholder structural type until we have a Relay key type to reference,
// if we start rendering something sub-issues related in the UI (which we currently don't)
type Issue = {readonly id: string}

type PreselectedDataTypes = {
  repository?: Repository
  template?: IssueCreatePayload

  parentIssue?: Issue
}

export type IssueCreateDataProviderProps = {
  optionConfig: SafeOptionConfig
  preselectedData: PreselectedDataTypes | undefined
  children: React.ReactNode
}

type IssueCreateDataContextState = {
  usedStorageKeyPrefix: string
  title: string
  setTitle: (value: string) => void
  reinitTitle: (value: string) => void

  body: string
  setBody: (value: string) => void
  reinitBody: (value: string) => void

  repository: Repository | undefined
  setRepository: (value: Repository | undefined) => void

  repositoryAbsolutePath: string

  template: IssueCreatePayload | undefined
  setTemplate: (value: IssueCreatePayload | undefined) => void

  preselectedRepository?: Repository | undefined
  preselectedTemplate?: IssueCreatePayload | undefined

  labels: Label[]
  setLabels: (value: Label[]) => void
  reinitLabels: (value: Label[]) => void

  assignees: Assignee[]
  setAssignees: (value: Assignee[]) => void
  reinitAssignees: (value: Assignee[]) => void

  projects: Project[]
  setProjects: (value: Project[]) => void
  reinitProjects: (value: Project[]) => void

  milestone: Milestone | null
  setMilestone: (value: Milestone | null) => void
  reinitMilestone: (value: Milestone | null) => void

  issueType: IssueType | null
  setIssueType: (value: IssueType | null) => void
  reinitIssueType: (value: IssueType | null) => void

  parentIssue: Issue | null

  originalTitle: string
  setOriginalTitle: (value: string) => void

  originalBody: string
  setOriginalBody: (value: string) => void

  setNewTitle: (newTitle: string) => void
  setNewBody: (newBody: string) => void

  clearMetadata: () => void
  clearSessionData: () => void
  clearSessionMetadata: () => void
  clearSessionTitleAndBody: () => void
  clearSessionCreateMore: () => void
  clearTitleAndBody: () => void
}

const IssueCreateDataContext = createContext<IssueCreateDataContextState | null>(null)

function getLabelsFromTemplate(template: IssueCreatePayload): Label[] {
  let initialLabels: Label[] = []
  if (template?.data) {
    initialLabels =
      template?.data.labels?.edges?.flatMap(e =>
        // eslint-disable-next-line no-restricted-syntax
        e?.node ? [readInlineData<LabelPickerLabel$key>(LabelFragment, e?.node)] : [],
      ) || []
  }
  return initialLabels
}

function getAssigneesFromTemplate(template: IssueCreatePayload): Assignee[] {
  let initialAssignees: Assignee[] = []
  if (template?.data) {
    initialAssignees =
      template?.data.assignees?.edges?.flatMap(e =>
        // eslint-disable-next-line no-restricted-syntax
        e?.node ? [readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, e?.node)] : [],
      ) || []
  }
  return initialAssignees
}

function getTitleFromTemplate(template: IssueCreatePayload): string {
  let initialTitle = ''
  if (template?.data) {
    initialTitle = template?.data.title || ''
  }
  return initialTitle
}

function getBodyFromTemplate(template: IssueCreatePayload): string {
  let initialBody = ''
  if (template?.data && instanceOfIssueTemplateData(template?.data)) {
    initialBody = template?.data.body || ''
  }
  return initialBody
}

function getProjectsFromTemplate(template: IssueCreatePayload): Project[] {
  let initialProjects: Project[] = []
  if (template?.data && instanceOfIssueFormData(template?.data)) {
    initialProjects =
      template.data.projects?.edges?.flatMap(e =>
        // eslint-disable-next-line no-restricted-syntax
        e?.node ? [readInlineData<ProjectPickerProject$key>(ProjectPickerProjectFragment, e?.node)] : [],
      ) || []
  }
  return initialProjects
}

function getIssueTypeFromTemplate(template: IssueCreatePayload): IssueType | null {
  let initialIssueType: IssueType | null = null
  if (template?.data && (instanceOfIssueFormData(template?.data) || instanceOfIssueTemplateData(template?.data))) {
    // eslint-disable-next-line no-restricted-syntax
    initialIssueType = readInlineData<IssueTypePickerIssueType$key>(IssueTypeFragment, template?.data.type) ?? null
  }
  return initialIssueType
}

export function IssueCreateDataContextProvider({
  optionConfig,
  preselectedData,
  children,
}: IssueCreateDataProviderProps) {
  const {storageKeyPrefix, issueCreateArguments} = optionConfig
  const {issueTitle, issueBody} = VALUES.localTitleAndBodyStorageKeys
  const {issueLabels, issueAssignees, issueProjects, issueMilestone, issueIssueType} = VALUES.localStorageMetadataKeys

  const [repository, setRepository] = useState<Repository | undefined>(preselectedData?.repository)
  const [template, setTemplateInternal] = useState<IssueCreatePayload | undefined>(preselectedData?.template)

  // add the template name to the storage key prefix to avoid conflicts between different templates
  const [usedStorageKeyPrefix, setUsedStorageKeyPrefix] = useState<string>(
    `${storageKeyPrefix}.${template?.fileName || BLANK_ISSUE_ID}`,
  )

  let initialTitle = ''
  if (issueCreateArguments?.initialValues?.discussion) {
    initialTitle = issueCreateArguments?.initialValues?.discussion.title
  } else if (issueCreateArguments?.initialValues?.title) {
    initialTitle = issueCreateArguments?.initialValues?.title
  } else if (template) {
    const templateTitle = getTitleFromTemplate(template)
    let userInputTitle = ''
    if (issueCreateArguments?.initialValues?.appendTitleToTemplate) {
      userInputTitle = ` ${issueCreateArguments?.initialValues?.appendTitleToTemplate}`
    }
    initialTitle = [templateTitle, userInputTitle].join('').trimStart()
  } else {
    if (issueCreateArguments?.initialValues?.appendTitleToTemplate) {
      initialTitle = issueCreateArguments?.initialValues?.appendTitleToTemplate
    }
  }
  const [title, setTitle, reinitTitle] = useSessionStorage<string>(issueTitle(usedStorageKeyPrefix), initialTitle)

  let initialBody = ''
  if (issueCreateArguments?.initialValues?.discussion) {
    initialBody = issueCreateArguments?.initialValues?.discussion.formattedBody
  } else if (issueCreateArguments?.initialValues?.body) {
    initialBody = issueCreateArguments?.initialValues?.body
  } else if (template) {
    initialBody = getBodyFromTemplate(template)
  }
  const [body, setBody, reinitBody] = useSessionStorage<string>(issueBody(usedStorageKeyPrefix), initialBody)

  let initialLabels: Label[] = []
  if (issueCreateArguments?.initialValues?.discussion) {
    initialLabels = issueCreateArguments?.initialValues?.discussion?.labels || []
  } else if (issueCreateArguments?.initialValues?.labels) {
    initialLabels = issueCreateArguments?.initialValues?.labels
  } else if (template) {
    initialLabels = getLabelsFromTemplate(template)
  }
  const [labels, setLabels, reinitLabels] = useSessionStorage<Label[]>(issueLabels(usedStorageKeyPrefix), initialLabels)

  let initialAssignees: Assignee[] = []
  if (issueCreateArguments?.initialValues?.assignees) {
    initialAssignees = issueCreateArguments?.initialValues?.assignees
  } else if (template) {
    initialAssignees = getAssigneesFromTemplate(template)
  }
  const [assignees, setAssignees, reinitAssignees] = useSessionStorage<Assignee[]>(
    issueAssignees(usedStorageKeyPrefix),
    initialAssignees,
  )

  let initialProjects: Project[] = []
  if (issueCreateArguments?.initialValues?.projects) {
    initialProjects = issueCreateArguments?.initialValues?.projects
  } else if (template) {
    initialProjects = getProjectsFromTemplate(template)
  }
  const [projects, setProjects, reinitProjects] = useSessionStorage<Project[]>(
    issueProjects(usedStorageKeyPrefix),
    initialProjects,
  )

  let initialMilestone: Milestone | null = null
  if (issueCreateArguments?.initialValues?.milestone) {
    initialMilestone = issueCreateArguments?.initialValues?.milestone
  }
  const [milestone, setMilestone, reinitMilestone] = useSessionStorage<Milestone | null>(
    issueMilestone(usedStorageKeyPrefix),
    initialMilestone,
  )

  let initialIssueType: IssueType | null = null
  if (issueCreateArguments?.initialValues?.type) {
    initialIssueType = issueCreateArguments?.initialValues?.type
  } else if (template) {
    initialIssueType = getIssueTypeFromTemplate(template)
  }
  const [issueType, setIssueType, reinitIssueType] = useSessionStorage<IssueType | null>(
    issueIssueType(usedStorageKeyPrefix),
    initialIssueType,
  )

  const [originalTitle, setOriginalTitle] = useState<string>(title)
  const [originalBody, setOriginalBody] = useState<string>(body)

  const setNewTitle = useCallback(
    (newTitle: string) => {
      setTitle(newTitle)
      setOriginalTitle(newTitle)
    },
    [setTitle, setOriginalTitle],
  )
  const setNewBody = useCallback(
    (newBody: string) => {
      setBody(newBody)
      setOriginalBody(newBody)
    },
    [setBody, setOriginalBody],
  )

  const clearMetadata = useCallback(() => {
    setAssignees([])
    setLabels([])
    setProjects([])
    setMilestone(null)
  }, [setAssignees, setLabels, setMilestone, setProjects])

  const clearSessionData = useCallback(() => {
    clearSessionStorage(storageKeys(usedStorageKeyPrefix))
  }, [usedStorageKeyPrefix])

  const clearSessionMetadata = useCallback(() => {
    clearSessionStorage(storageMetadataKeys(usedStorageKeyPrefix))
  }, [usedStorageKeyPrefix])

  const clearSessionTitleAndBody = useCallback(() => {
    clearSessionStorage(storageTitleAndBodyKeys(usedStorageKeyPrefix))
  }, [usedStorageKeyPrefix])

  const clearSessionCreateMore = useCallback(() => {
    clearSessionStorage([`config.${VALUES.localStorageKeys.issueCreateMore(storageKeyPrefix)}`])
  }, [storageKeyPrefix])

  const clearTitleAndBody = useCallback(() => {
    setTitle('')
    setBody('')
    setOriginalTitle('')
    setOriginalBody('')
  }, [setTitle, setBody, setOriginalTitle, setOriginalBody])

  const origin = ssrSafeLocation?.origin ?? ''
  const repoNwo = repository?.nameWithOwner ?? ''
  const repositoryAbsolutePath = useMemo(() => `${origin}/${repoNwo}`, [origin, repoNwo])

  const parentIssue = preselectedData?.parentIssue ?? null

  const setTemplate = useCallback(
    (newTemplate: IssueCreatePayload | undefined) => {
      setTemplateInternal(newTemplate)
      setUsedStorageKeyPrefix(`${storageKeyPrefix}.${newTemplate?.fileName || BLANK_ISSUE_ID}`)
    },
    [storageKeyPrefix],
  )

  const contextValue: IssueCreateDataContextState = useMemo(() => {
    return {
      reinitTitle,
      reinitBody,
      reinitAssignees,
      reinitLabels,
      reinitProjects,
      reinitMilestone,
      reinitIssueType,
      usedStorageKeyPrefix,
      clearSessionData,
      clearSessionMetadata,
      clearSessionTitleAndBody,
      clearSessionCreateMore,
      clearMetadata,
      clearTitleAndBody,
      setNewTitle,
      setNewBody,

      originalTitle,
      setOriginalTitle,
      originalBody,
      setOriginalBody,
      title,
      setTitle,
      body,
      setBody,
      repository,
      setRepository,
      repositoryAbsolutePath,
      template,
      setTemplate,
      preselectedRepository: preselectedData?.repository,
      preselectedTemplate: preselectedData?.template,
      labels,
      setLabels,
      assignees,
      setAssignees,
      projects,
      setProjects,
      milestone,
      setMilestone,
      issueType,
      setIssueType,
      parentIssue,
    }
  }, [
    reinitTitle,
    reinitBody,
    reinitAssignees,
    reinitLabels,
    reinitProjects,
    reinitMilestone,
    reinitIssueType,
    usedStorageKeyPrefix,
    clearSessionData,
    clearSessionMetadata,
    clearSessionTitleAndBody,
    clearSessionCreateMore,
    clearMetadata,
    clearTitleAndBody,
    setNewTitle,
    setNewBody,
    originalTitle,
    originalBody,
    title,
    setTitle,
    body,
    setBody,
    repository,
    repositoryAbsolutePath,
    template,
    setTemplate,
    preselectedData?.repository,
    preselectedData?.template,
    labels,
    setLabels,
    assignees,
    setAssignees,
    projects,
    setProjects,
    milestone,
    setMilestone,
    issueType,
    setIssueType,
    parentIssue,
  ])

  return <IssueCreateDataContext.Provider value={contextValue}>{children}</IssueCreateDataContext.Provider>
}

export const useIssueCreateDataContext = () => {
  const context = useContext(IssueCreateDataContext)
  if (!context) {
    throw new Error('useIssueCreateDataContext must be used within a IssueCreateDataContextProvider.')
  }

  return context
}
