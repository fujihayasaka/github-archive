import {Box} from '@primer/react'
import {useIssueCreateDataContext} from './../contexts/IssueCreateDataContext'
import {useIssueCreateConfigContext} from './../contexts/IssueCreateConfigContext'
import {CreateIssueMilestonesSection} from '@github-ui/issue-metadata/MilestonesSection'
import {CreateIssueAssigneesSection} from '@github-ui/issue-metadata/AssigneesSection'
import {CreateIssueLabelsSection} from '@github-ui/issue-metadata/LabelsSection'
import {CreateIssueProjectsSection} from '@github-ui/issue-metadata/ProjectsSection'
import {CreateIssueIssueTypesSection} from '@github-ui/issue-metadata/TypesSection'
import {CreateIssueFieldsSection} from '@github-ui/issue-metadata/FieldsSection'
import type {SharedMetadataProps} from './MetadataSelectors'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

export const MetadataSidebar = ({
  setMilestoneCallback,
  setIssueTypeCallback,
  canAssign,
  canLabel,
  canMilestone,
  canProject,
  canType,
  issueTypesEnabled,
}: SharedMetadataProps) => {
  const {optionConfig} = useIssueCreateConfigContext()
  const {repository, labels, setLabels, assignees, setAssignees, projects, setProjects, milestone, issueType} =
    useIssueCreateDataContext()

  // this flag is checked at the org level, so we cannot use isFeatureEnabled() here
  // eslint-disable-next-line @github-ui/github-monorepo/no-use-feature-flags
  const issue_fields = useFeatureFlag('issue_fields')

  const sharedConfigProps = {
    insidePortal: optionConfig.insidePortal,
    shortcutEnabled: optionConfig.singleKeyShortcutsEnabled,
  }

  if (!repository) {
    return null
  }

  return (
    <Box sx={{display: 'flex', flexDirection: 'column', gap: 2, flexWrap: 'wrap'}}>
      <h2 className="sr-only">Metadata</h2>
      {repository && (
        <CreateIssueAssigneesSection
          sx={{flexGrow: 1}}
          repo={repository.name}
          owner={repository.owner.login}
          readonly={!canAssign}
          assignees={assignees}
          onSelectionChange={setAssignees}
          maximumAssignees={repository.planFeatures.maximumAssignees}
          {...sharedConfigProps}
        />
      )}
      <CreateIssueLabelsSection
        repo={repository.name}
        owner={repository.owner.login}
        readonly={!canLabel}
        labels={labels}
        onSelectionChange={setLabels}
        {...sharedConfigProps}
      />
      {issueTypesEnabled && (
        <CreateIssueIssueTypesSection
          owner={repository.owner.login}
          repo={repository.name}
          {...sharedConfigProps}
          viewerCanType={canType}
          type={issueType}
          onSelectionChange={setIssueTypeCallback}
        />
      )}
      {issue_fields && <CreateIssueFieldsSection owner={repository.owner.login} {...sharedConfigProps} />}
      <CreateIssueProjectsSection
        owner={repository.owner.login}
        repo={repository.name}
        projects={projects}
        readonly={!canProject}
        onSelectionChange={setProjects}
        {...sharedConfigProps}
      />
      <CreateIssueMilestonesSection
        sx={{flexGrow: 1}}
        repo={repository.name}
        owner={repository.owner.login}
        milestone={milestone}
        onSelectionChange={setMilestoneCallback}
        viewerCanSetMilestone={canMilestone ?? false}
        {...sharedConfigProps}
      />
    </Box>
  )
}
