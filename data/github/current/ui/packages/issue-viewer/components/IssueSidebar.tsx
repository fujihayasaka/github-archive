import {Suspense, useMemo} from 'react'
import type {OptionConfig} from './OptionConfig'
import type {IssueViewerViewer$data} from './__generated__/IssueViewerViewer.graphql'

import {EditIssueMilestonesSection} from '@github-ui/issue-metadata/MilestonesSection'
import {EditIssueIssueTypeSection} from '@github-ui/issue-metadata/TypesSection'
import {EditIssueAssigneesSection} from '@github-ui/issue-metadata/AssigneesSection'
import {OptionsSection} from './sections/OptionsSection'
import {graphql, useFragment} from 'react-relay'
import type {IssueSidebarPrimaryQuery$key} from './__generated__/IssueSidebarPrimaryQuery.graphql'
import {IssueSidebarLazySections, IssueSidebarLazySectionsFallback} from './IssueSidebarLazySections'
import {EditIssueProjectsSection, ProjectsSectionFallback} from '@github-ui/issue-metadata/ProjectsSection'
import {EditIssueLabelsSection} from '@github-ui/issue-metadata/LabelsSection'
import {EditIssueFieldsSection} from '@github-ui/issue-metadata/FieldsSection'
import type {IssueSidebarSecondary$key} from './__generated__/IssueSidebarSecondary.graphql'
import type {IssueSidebarLazySections$key} from './__generated__/IssueSidebarLazySections.graphql'
import type {AssigneesSectionLazyFragment$key} from '@github-ui/issue-metadata/AssigneesSectionLazyFragment.graphql'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {FeatureFlags} from '@primer/react/experimental'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

type IssueSidebarProps = {
  sidebarKey: IssueSidebarPrimaryQuery$key
  sidebarSecondaryKey?: IssueSidebarSecondary$key | IssueSidebarLazySections$key
  optionConfig: OptionConfig
  viewer: IssueViewerViewer$data | null
}

const IssueSidebarSecondary = graphql`
  fragment IssueSidebarSecondary on Issue {
    ...OptionsSectionSecondary
    ...AssigneesSectionLazyFragment
  }
`

export const IssueSidebarPrimaryGraphqlQuery = graphql`
  fragment IssueSidebarPrimaryQuery on Issue @argumentDefinitions(allowedOwner: {type: "String", defaultValue: null}) {
    ...AssigneesSectionFragment
    ...LabelsSectionFragment
    ...ProjectsSectionFragment @arguments(allowedOwner: $allowedOwner)
    ...MilestonesSectionFragment
    ...OptionsSectionFragment
    ...TypesSectionFragment
    ...FieldsSectionFragment
  }
`

export function IssueSidebar({sidebarKey, sidebarSecondaryKey, optionConfig, viewer}: IssueSidebarProps) {
  const issue = useFragment(IssueSidebarPrimaryGraphqlQuery, sidebarKey)
  const issueSecondary = useFragment(IssueSidebarSecondary, sidebarSecondaryKey as IssueSidebarSecondary$key)

  // this flag is checked at the org level, so we cannot use isFeatureEnabled() here
  const issue_fields = useFeatureFlag('issue_fields')

  const sidebar = useMemo(
    () => (
      <FeatureFlags
        flags={{
          primer_react_select_panel_with_modern_action_list: true,
        }}
      >
        <EditIssueAssigneesSection
          issue={issue}
          viewer={viewer}
          lazyKey={issueSecondary as AssigneesSectionLazyFragment$key}
          onIssueUpdate={optionConfig.onIssueUpdate}
          singleKeyShortcutsEnabled={optionConfig.singleKeyShortcutsEnabled || false}
          insideSidePanel={optionConfig.insideSidePanel}
        />
        <EditIssueLabelsSection
          issue={issue}
          onIssueUpdate={optionConfig.onIssueUpdate}
          singleKeyShortcutsEnabled={optionConfig.singleKeyShortcutsEnabled || false}
          insideSidePanel={optionConfig.insideSidePanel}
        />
        <EditIssueIssueTypeSection
          issue={issue}
          singleKeyShortcutsEnabled={optionConfig.singleKeyShortcutsEnabled || false}
          onIssueUpdate={optionConfig.onIssueUpdate}
          insideSidePanel={optionConfig.insideSidePanel}
        />
        {issue_fields && (
          <EditIssueFieldsSection
            issue={issue}
            singleKeyShortcutsEnabled={optionConfig.singleKeyShortcutsEnabled || false}
            onIssueUpdate={optionConfig.onIssueUpdate}
            insideSidePanel={optionConfig.insideSidePanel}
          />
        )}
        <Suspense fallback={<ProjectsSectionFallback />}>
          <ErrorBoundary fallback={<ProjectsSectionFallback />}>
            <EditIssueProjectsSection
              selectedProjectId={optionConfig.selectedProjectId}
              allowedProjectOwner={optionConfig.allowedProjectOwner}
              issueOrPullRequest={issue}
              onIssueUpdate={optionConfig.onIssueUpdate}
              insideSidePanel={optionConfig.insideSidePanel}
            />
          </ErrorBoundary>
        </Suspense>
        <EditIssueMilestonesSection
          issue={issue}
          onIssueUpdate={optionConfig.onIssueUpdate}
          singleKeyShortcutsEnabled={optionConfig.singleKeyShortcutsEnabled || false}
          insideSidePanel={optionConfig.insideSidePanel}
        />
        <Suspense fallback={<IssueSidebarLazySectionsFallback />}>
          <IssueSidebarLazySections
            onLinkClick={optionConfig.onLinkClick}
            onIssueUpdate={optionConfig.onIssueUpdate}
            insideSidePanel={optionConfig.insideSidePanel}
            issueSidebarSecondaryKey={sidebarSecondaryKey as IssueSidebarLazySections$key}
            viewer={viewer}
          />
        </Suspense>
        <OptionsSection issue={issue} optionsSectionSecondary={issueSecondary} optionConfig={optionConfig} />
      </FeatureFlags>
    ),
    [issue, issueSecondary, issue_fields, optionConfig, sidebarSecondaryKey, viewer],
  )

  return sidebar
}
