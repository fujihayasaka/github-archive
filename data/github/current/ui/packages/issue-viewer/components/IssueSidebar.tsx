import {Suspense, useMemo} from 'react'
import type {OptionConfig} from './OptionConfig'
import type {IssueViewerViewer$data} from './__generated__/IssueViewerViewer.graphql'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

import {EditIssueMilestonesSection} from '@github-ui/issue-metadata/MilestonesSection'
import {EditIssueIssueTypeSection} from '@github-ui/issue-metadata/TypesSection'
import {EditIssueAssigneesSection} from '@github-ui/issue-metadata/AssigneesSection'
import {OldExperienceReloadBanner} from './OldExperienceReloadBanner'
import {OptionsSection} from './sections/OptionsSection'
import {graphql, useFragment} from 'react-relay'
import type {IssueSidebarPrimaryQuery$key} from './__generated__/IssueSidebarPrimaryQuery.graphql'
import {IssueSidebarLazySections, IssueSidebarLazySectionsFallback} from './IssueSidebarLazySections'
import {EditIssueProjectsSection, ProjectsSectionFallback} from '@github-ui/issue-metadata/ProjectsSection'
import {EditIssueLabelsSection} from '@github-ui/issue-metadata/LabelsSection'
import type {IssueSidebarSecondary$key} from './__generated__/IssueSidebarSecondary.graphql'
import type {IssueSidebarLazySections$key} from './__generated__/IssueSidebarLazySections.graphql'
import type {AssigneesSectionLazyFragment$key} from '@github-ui/issue-metadata/AssigneesSectionLazyFragment.graphql'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {FeatureFlags} from '@primer/react/experimental'
import {isFeatureEnabled} from '@github-ui/feature-flags'

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
  }
`

export function IssueSidebar({sidebarKey, sidebarSecondaryKey, optionConfig, viewer}: IssueSidebarProps) {
  const issue = useFragment(IssueSidebarPrimaryGraphqlQuery, sidebarKey)
  const issueSecondary = useFragment(IssueSidebarSecondary, sidebarSecondaryKey as IssueSidebarSecondary$key)

  const {sub_issues} = useFeatureFlags()

  const issues_react_new_select_panel = isFeatureEnabled('issues_react_new_select_panel')

  const sidebar = useMemo(
    () => (
      <FeatureFlags
        flags={{
          primer_react_select_panel_with_modern_action_list: issues_react_new_select_panel,
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
        <Suspense fallback={<IssueSidebarLazySectionsFallback subIssuesEnabled={sub_issues} />}>
          <IssueSidebarLazySections
            onLinkClick={optionConfig.onLinkClick}
            onIssueUpdate={optionConfig.onIssueUpdate}
            subIssuesEnabled={sub_issues}
            insideSidePanel={optionConfig.insideSidePanel}
            issueSidebarSecondaryKey={sidebarSecondaryKey as IssueSidebarLazySections$key}
            viewer={viewer}
          />
        </Suspense>
        <OptionsSection optionsSection={issue} optionsSectionSecondary={issueSecondary} optionConfig={optionConfig} />
        {optionConfig.showReloadInOldExperience && <OldExperienceReloadBanner />}
      </FeatureFlags>
    ),
    [issues_react_new_select_panel, issue, issueSecondary, optionConfig, sidebarSecondaryKey, sub_issues, viewer],
  )

  return sidebar
}
