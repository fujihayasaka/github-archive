import {useCallback} from 'react'

import {graphql, readInlineData} from 'relay-runtime'
import {
  instanceOfBlankIssueData,
  instanceOfIssueFormData,
  instanceOfIssueTemplateData,
  IssueCreationKind,
  type IssueCreatePayload,
} from './utils/model'
import type {IssueCreateValueTypes} from './utils/template-args'
import {AssigneeFragment} from '@github-ui/item-picker/AssigneePicker'
import type {AssigneePickerAssignee$key} from '@github-ui/item-picker/AssigneePicker.graphql'
import {IssueTypeFragment} from '@github-ui/item-picker/IssueTypePicker'
import type {
  IssueTypePickerIssueType$data,
  IssueTypePickerIssueType$key,
} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'
import {LabelFragment} from '@github-ui/item-picker/LabelPicker'
import type {LabelPickerLabel$key} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import {ProjectPickerProjectFragment} from '@github-ui/item-picker/ProjectPicker'
import type {ProjectPickerProject$key} from '@github-ui/item-picker/ProjectPickerProject.graphql'
import {DisplayMode} from './utils/display-mode'
import {useIssueCreateDataContext} from './contexts/IssueCreateDataContext'
import type {Repository} from '@github-ui/item-picker/RepositoryPicker'
import type {IssueCreateOptionConfig} from './utils/option-config'
import type {useHandleTemplateChange$key} from './__generated__/useHandleTemplateChange.graphql'
import type {useHandleTemplateChangeIssueTemplate$key} from './__generated__/useHandleTemplateChangeIssueTemplate.graphql'
import type {useHandleTemplateChangeIssueForm$key} from './__generated__/useHandleTemplateChangeIssueForm.graphql'
import {getTemplateUrl} from './utils/urls'

type useHandleTemplateChangeProps = {
  optionConfig: IssueCreateOptionConfig
  repository: Repository | undefined
  navigate: (url: string) => void
  setDisplayMode: (mode: DisplayMode) => void
}
export const UseHandleTemplateChangeIssueTemplateFragment = graphql`
  fragment useHandleTemplateChangeIssueTemplate on IssueTemplate @inline {
    # this field can go once we refactor the issues create dialog
    # eslint-disable-next-line relay/unused-fields
    __id
    __typename
    name
    filename
    body
    title
    labels(first: 20, orderBy: {field: NAME, direction: ASC}) {
      edges {
        node {
          ...LabelPickerLabel
        }
      }
    }
    assignees(first: 10) {
      edges {
        node {
          ...AssigneePickerAssignee
        }
      }
    }
    type {
      ...IssueTypePickerIssueType
    }
  }
`

export const UseHandleTemplateChangeIssueFormFragment = graphql`
  fragment useHandleTemplateChangeIssueForm on IssueForm @inline {
    # this field can go once we refactor the issues create dialog
    # eslint-disable-next-line relay/unused-fields
    __id
    __typename
    name
    filename
    title
    # This is required to make the form work correctly
    # eslint-disable-next-line relay/must-colocate-fragment-spreads
    ...IssueFormElements_templateElements
    labels(first: 20, orderBy: {field: NAME, direction: ASC}) {
      edges {
        node {
          ...LabelPickerLabel
        }
      }
    }
    assignees(first: 10) {
      edges {
        node {
          ...AssigneePickerAssignee
        }
      }
    }
    projects(first: 20) {
      edges {
        node {
          ...ProjectPickerProject
        }
      }
    }
    type {
      ...IssueTypePickerIssueType
    }
  }
`

export const getSelectedTemplate = (repository: useHandleTemplateChange$key): IssueCreatePayload | undefined => {
  // eslint-disable-next-line no-restricted-syntax
  const data = readInlineData(
    graphql`
      fragment useHandleTemplateChange on Repository
      @inline
      @argumentDefinitions(filename: {type: "String!", defaultValue: ""}) {
        issueTemplate(filename: $filename) {
          ...useHandleTemplateChangeIssueTemplate
        }

        issueForm(filename: $filename) {
          ...useHandleTemplateChangeIssueForm
        }
      }
    `,
    repository,
  )
  let fetchedTemplate = undefined
  if (data.issueTemplate) {
    // eslint-disable-next-line no-restricted-syntax
    const templateData = readInlineData<useHandleTemplateChangeIssueTemplate$key>(
      UseHandleTemplateChangeIssueTemplateFragment,
      data.issueTemplate,
    )
    fetchedTemplate = {
      name: templateData.name,
      fileName: templateData.filename,
      kind: IssueCreationKind.IssueTemplate,
      data: templateData,
    }
  } else if (data.issueForm) {
    // eslint-disable-next-line no-restricted-syntax
    const templateData = readInlineData<useHandleTemplateChangeIssueForm$key>(
      UseHandleTemplateChangeIssueFormFragment,
      data.issueForm,
    )
    fetchedTemplate = {
      name: templateData.name,
      fileName: templateData.filename,
      kind: IssueCreationKind.IssueForm,
      data: templateData,
    }
  }
  return fetchedTemplate
}

export const useHandleTemplateChange = ({
  optionConfig,
  repository,
  navigate,
  setDisplayMode,
}: useHandleTemplateChangeProps) => {
  const {
    setTemplate,
    reinitTitle,
    reinitBody,
    reinitAssignees,
    reinitLabels,
    reinitProjects,
    reinitMilestone,
    reinitIssueType,
  } = useIssueCreateDataContext()
  return useCallback(
    (selectedTemplate?: IssueCreatePayload, enforcedInitialValues?: IssueCreateValueTypes, enforceNavigate = false) => {
      setTemplate(selectedTemplate)

      let newTitle = ''
      if (enforcedInitialValues?.discussion) {
        newTitle = enforcedInitialValues.discussion.title
      } else if (enforcedInitialValues?.title) {
        newTitle = enforcedInitialValues.title || ''
      } else {
        const templateTitle = selectedTemplate?.data.title || ''
        let userInputTitle = ''
        if (enforcedInitialValues?.appendTitleToTemplate) {
          userInputTitle = ` ${enforcedInitialValues.appendTitleToTemplate}`
        }
        newTitle = [templateTitle, userInputTitle].join('').trimStart()
      }

      reinitTitle(newTitle)

      let newBody = ''
      if (enforcedInitialValues?.discussion) {
        newBody = enforcedInitialValues.discussion.formattedBody || ''
      } else if (enforcedInitialValues?.body) {
        newBody = enforcedInitialValues.body || ''
      } else if (
        selectedTemplate &&
        (instanceOfIssueTemplateData(selectedTemplate.data) || instanceOfBlankIssueData(selectedTemplate.data))
      ) {
        newBody = selectedTemplate.data.body || ''
      }
      reinitBody(newBody)

      let templateLabels = []
      if (enforcedInitialValues?.discussion) {
        templateLabels = enforcedInitialValues.discussion?.labels || []
      } else if (enforcedInitialValues?.labels) {
        templateLabels = enforcedInitialValues.labels
      } else {
        templateLabels =
          selectedTemplate?.data.labels?.edges?.flatMap(e =>
            // eslint-disable-next-line no-restricted-syntax
            e?.node ? [readInlineData<LabelPickerLabel$key>(LabelFragment, e?.node)] : [],
          ) || []
      }

      reinitLabels(templateLabels)

      const templateAssignees =
        enforcedInitialValues?.assignees ??
        ((selectedTemplate?.data.assignees?.edges || []).flatMap(e =>
          // eslint-disable-next-line no-restricted-syntax
          e?.node ? [readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, e?.node)] : [],
        ) ||
          [])
      reinitAssignees(templateAssignees)

      if (enforcedInitialValues?.projects) {
        reinitProjects(enforcedInitialValues.projects)
      } else if (selectedTemplate && instanceOfIssueFormData(selectedTemplate?.data)) {
        const templateProjects =
          selectedTemplate.data.projects?.edges?.flatMap(e =>
            // eslint-disable-next-line no-restricted-syntax
            e?.node ? [readInlineData<ProjectPickerProject$key>(ProjectPickerProjectFragment, e?.node)] : [],
          ) || []
        reinitProjects(templateProjects)
      }

      if (enforcedInitialValues?.milestone) {
        reinitMilestone(enforcedInitialValues?.milestone)
      }

      let templateType: IssueTypePickerIssueType$data | null = enforcedInitialValues?.type ?? null
      if (
        selectedTemplate &&
        !templateType &&
        (instanceOfIssueFormData(selectedTemplate.data) || instanceOfIssueTemplateData(selectedTemplate.data)) &&
        selectedTemplate.data.type !== undefined
      ) {
        templateType =
          // eslint-disable-next-line no-restricted-syntax
          readInlineData<IssueTypePickerIssueType$key>(IssueTypeFragment, selectedTemplate.data.type) ?? null
      }
      reinitIssueType(templateType ?? null)

      if (!enforcedInitialValues || enforceNavigate) {
        if (optionConfig.navigateToFullScreenOnTemplateChoice && repository && selectedTemplate) {
          navigate(getTemplateUrl(repository.nameWithOwner, selectedTemplate.fileName))
        } else {
          setDisplayMode(DisplayMode.IssueCreation)
        }
      }
    },
    [
      setTemplate,
      reinitTitle,
      reinitBody,
      reinitLabels,
      reinitAssignees,
      reinitIssueType,
      reinitProjects,
      reinitMilestone,
      optionConfig.navigateToFullScreenOnTemplateChoice,
      repository,
      navigate,
      setDisplayMode,
    ],
  )
}
