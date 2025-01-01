import type {IssueCreateDiscussionData, IssueCreateMetadataTypes} from '@github-ui/issue-create/TemplateArgs'
import {AssigneeFragment} from '@github-ui/item-picker/AssigneePicker'
import type {AssigneePickerAssignee$key} from '@github-ui/item-picker/AssigneePicker.graphql'
import {LabelFragment} from '@github-ui/item-picker/LabelPicker'
import type {LabelPickerLabel$key} from '@github-ui/item-picker/LabelPickerLabel.graphql'

import type {MilestonePickerMilestone$key} from '@github-ui/item-picker/MilestonePickerMilestone.graphql'
import {MilestoneFragment} from '@github-ui/item-picker/MilestonePicker'
import {graphql, type PreloadedQuery, readInlineData, useFragment, usePreloadedQuery} from 'react-relay'

import type {InternalIssueNewPageUrlArgumentsMetadataQuery} from './__generated__/InternalIssueNewPageUrlArgumentsMetadataQuery.graphql'
import {ProjectPickerProjectFragment} from '@github-ui/item-picker/ProjectPicker'
import type {ProjectPickerProject$key} from '@github-ui/item-picker/ProjectPickerProject.graphql'
import {IssueTypeFragment} from '@github-ui/item-picker/IssueTypePicker'
import type {IssueTypePickerIssueType$key} from '@github-ui/item-picker/IssueTypePickerIssueType.graphql'
import {IssueCreatePage} from '@github-ui/issue-create/IssueCreatePage'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from '../../types/app-payload'
import {VALUES} from '../../constants/values'
import type {InternalIssueNewPageUrlArgumentsMetadata$key} from './__generated__/InternalIssueNewPageUrlArgumentsMetadata.graphql'

export const InternalIssueNewPageUrlArgumentsMetadata = graphql`
  query InternalIssueNewPageUrlArgumentsMetadataQuery(
    $owner: String!
    $name: String!
    $withAssignees: Boolean = false
    $assigneeLogins: String = ""
    $withLabels: Boolean = false
    $labelNames: String = ""
    $withMilestone: Boolean = false
    $milestoneTitle: String = ""
    $type: String = ""
    $withType: Boolean = false
    $withProjects: Boolean = false
    $projectNumbers: [Int!] = []
    $withTriagePermission: Boolean = false
    $discussionNumber: Int = 0
    $includeDiscussion: Boolean = false
    $templateFilter: String = ""
    $withTemplate: Boolean = false
  ) {
    repository(owner: $owner, name: $name) {
      ...InternalIssueNewPageUrlArgumentsMetadata
        @arguments(
          withAssignees: $withAssignees
          assigneeLogins: $assigneeLogins
          withLabels: $withLabels
          labelNames: $labelNames
          withMilestone: $withMilestone
          milestoneTitle: $milestoneTitle
          type: $type
          withType: $withType
          withProjects: $withProjects
          projectNumbers: $projectNumbers
          withTriagePermission: $withTriagePermission
          discussionNumber: $discussionNumber
          includeDiscussion: $includeDiscussion
          templateFilter: $templateFilter
          withTemplate: $withTemplate
        )
    }
  }
`

export type InternalIssueNewPageProps = {
  urlParameterQueryData: PreloadedQuery<InternalIssueNewPageUrlArgumentsMetadataQuery>
}

export const InternalIssueNewPageWithUrlParams = ({urlParameterQueryData}: InternalIssueNewPageProps) => {
  const repositoryData = usePreloadedQuery<InternalIssueNewPageUrlArgumentsMetadataQuery>(
    InternalIssueNewPageUrlArgumentsMetadata,
    urlParameterQueryData,
  )?.repository

  if (!repositoryData) {
    return <div>Repository not found</div>
  }
  return <InternalIssueNewPageWithUrlParamsInternal repository={repositoryData} />
}

const InternalIssueNewPageWithUrlParamsInternal = ({
  repository,
}: {
  repository: InternalIssueNewPageUrlArgumentsMetadata$key
}) => {
  const appPayload = useAppPayload<AppPayload>()

  const repositoryData = useFragment(
    graphql`
      fragment InternalIssueNewPageUrlArgumentsMetadata on Repository
      @argumentDefinitions(
        withAssignees: {type: "Boolean!", defaultValue: false}
        assigneeLogins: {type: "String!", defaultValue: ""}
        withLabels: {type: "Boolean!", defaultValue: false}
        labelNames: {type: "String!", defaultValue: ""}
        withMilestone: {type: "Boolean!", defaultValue: false}
        milestoneTitle: {type: "String!", defaultValue: ""}
        type: {type: "String!", defaultValue: ""}
        withType: {type: "Boolean!", defaultValue: false}
        withProjects: {type: "Boolean!", defaultValue: false}
        projectNumbers: {type: "[Int!]!", defaultValue: []}
        withTriagePermission: {type: "Boolean!", defaultValue: false}
        discussionNumber: {type: "Int", defaultValue: 0}
        includeDiscussion: {type: "Boolean!", defaultValue: false}
        templateFilter: {type: "String!", defaultValue: ""}
        withTemplate: {type: "Boolean!", defaultValue: false}
      ) {
        ...IssueCreatePage @arguments(templateFilter: $templateFilter, withTemplate: $withTemplate)
        viewerIssueCreationPermissions {
          assignable @include(if: $withAssignees)
          labelable @include(if: $withLabels)
          milestoneable @include(if: $withMilestone)
          triageable @include(if: $withTriagePermission)
          typeable @include(if: $withType)
        }
        suggestedActors(capabilities: [CAN_BE_ASSIGNED], first: 10, loginNames: $assigneeLogins)
          @include(if: $withAssignees) {
          nodes {
            ...AssigneePickerAssignee
          }
        }
        labels(first: 20, names: $labelNames) @include(if: $withLabels) {
          nodes {
            ...LabelPickerLabel
          }
        }
        discussion(number: $discussionNumber) @include(if: $includeDiscussion) {
          formattedBody
          title
          labels(first: 20, orderBy: {field: NAME, direction: ASC}) {
            edges {
              node {
                ...LabelPickerLabel
              }
            }
          }
        }
        milestoneByTitle(title: $milestoneTitle) @include(if: $withMilestone) {
          ...MilestonePickerMilestone
        }
        issueType(name: $type) @include(if: $withType) {
          ...IssueTypePickerIssueType
        }
        owner {
          ... on ProjectV2Owner {
            projectsV2ByNumber(first: 20, numbers: $projectNumbers) @include(if: $withProjects) {
              nodes {
                ...ProjectPickerProject
              }
            }
          }
        }
      }
    `,
    repository,
  )

  const assigneeNodes = repositoryData.suggestedActors?.nodes
  const assignees =
    assigneeNodes && repositoryData.viewerIssueCreationPermissions?.assignable
      ? // eslint-disable-next-line no-restricted-syntax
        assigneeNodes.flatMap(e => (e ? [readInlineData<AssigneePickerAssignee$key>(AssigneeFragment, e)] : []))
      : undefined

  const labelNodes = repositoryData?.labels?.nodes
  const labels =
    labelNodes && repositoryData.viewerIssueCreationPermissions?.labelable
      ? // eslint-disable-next-line no-restricted-syntax
        labelNodes.flatMap(e => (e ? [readInlineData<LabelPickerLabel$key>(LabelFragment, e)] : []))
      : undefined

  const projectNodes = repositoryData?.owner?.projectsV2ByNumber?.nodes
  const projects =
    projectNodes && repositoryData.viewerIssueCreationPermissions?.triageable
      ? projectNodes.flatMap(e =>
          // eslint-disable-next-line no-restricted-syntax
          e ? [readInlineData<ProjectPickerProject$key>(ProjectPickerProjectFragment, e)] : [],
        )
      : undefined

  const milestone =
    repositoryData?.milestoneByTitle && repositoryData.viewerIssueCreationPermissions?.milestoneable
      ? // eslint-disable-next-line no-restricted-syntax
        readInlineData<MilestonePickerMilestone$key>(MilestoneFragment, repositoryData?.milestoneByTitle)
      : undefined

  const issueType =
    repositoryData?.issueType &&
    repositoryData.viewerIssueCreationPermissions?.triageable &&
    repositoryData.viewerIssueCreationPermissions?.typeable
      ? // eslint-disable-next-line no-restricted-syntax
        readInlineData<IssueTypePickerIssueType$key>(IssueTypeFragment, repositoryData?.issueType)
      : undefined

  const discussion = repositoryData?.discussion
    ? ({
        title: repositoryData.discussion.title,
        formattedBody: repositoryData.discussion.formattedBody,
        labels: repositoryData.discussion.labels?.edges?.flatMap(e =>
          // eslint-disable-next-line no-restricted-syntax
          e?.node ? [readInlineData<LabelPickerLabel$key>(LabelFragment, e?.node)] : [],
        ),
      } as IssueCreateDiscussionData)
    : undefined

  const initialMetadataValues: IssueCreateMetadataTypes = {
    ...(assignees !== undefined && {assignees}),
    ...(labels !== undefined && {labels}),
    ...(milestone !== undefined && {milestone}),
    ...(projects !== undefined && {projects}),
    ...(issueType !== undefined && {type: issueType}),
    ...(discussion !== undefined && {discussion}),
  }
  const storageKeyPrefix = VALUES.storageKeyPrefix(appPayload)
  const pasteUrlsAsPlainText = appPayload?.current_user_settings?.paste_url_link_as_plain_text || false
  const useMonospaceFont = appPayload?.current_user_settings?.use_monospace_font || false
  const emojiSkinTonePreference = appPayload?.current_user_settings?.preferred_emoji_skin_tone
  const singleKeyShortcutsEnabled = appPayload?.current_user_settings?.use_single_key_shortcut || false
  const copilotShowFunctionality = appPayload?.current_user_settings?.copilot_show_functionality || false

  return (
    <IssueCreatePage
      initialMetadataValues={initialMetadataValues}
      storageKeyPrefix={storageKeyPrefix}
      pasteUrlsAsPlainText={pasteUrlsAsPlainText}
      useMonospaceFont={useMonospaceFont}
      emojiSkinTonePreference={emojiSkinTonePreference}
      singleKeyShortcutsEnabled={singleKeyShortcutsEnabled}
      copilotShowFunctionality={copilotShowFunctionality}
      currentRepository={repositoryData}
    />
  )
}
