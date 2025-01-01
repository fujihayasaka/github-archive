import type {AssigneeRepositoryPickerProps} from '@github-ui/item-picker/AssigneePicker'
import {AssigneeRepositoryPicker} from '@github-ui/item-picker/AssigneePicker'
import {DefaultAssigneePickerAnchor} from '@github-ui/item-picker/DefaultAssigneePickerAnchor'

import {AlertIcon, IssueOpenedIcon, MilestoneIcon, TableIcon} from '@primer/octicons-react'
import {Box} from '@primer/react'
import {Suspense, type RefObject} from 'react'
import {MetadataFooterLoading} from './../metadata/MetadataFooterLoading'
import {useIssueCreateDataContext} from './../contexts/IssueCreateDataContext'
import {useIssueCreateConfigContext} from './../contexts/IssueCreateConfigContext'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {DefaultLabelAnchor, LabelPicker} from '@github-ui/item-picker/LabelPicker'
import {DefaultMilestonePickerAnchor, MilestonePicker} from '@github-ui/item-picker/MilestonePicker'
import {DefaultProjectPickerAnchor, ProjectPicker} from '@github-ui/item-picker/ProjectPicker'
import {SharedPicker} from '@github-ui/item-picker/SharedPicker'
import type {SharedMetadataProps} from './MetadataSelectors'
import {CompressedAssigneeAnchor} from '@github-ui/item-picker/CompressedAssigneeAnchor'
import {DefaultIssueTypePickerFooterAnchor, IssueTypePicker} from '@github-ui/item-picker/IssueTypePicker'

export const MetadataFooter = ({
  repo,
  owner,
  setMilestoneCallback,
  canAssign,
  canLabel,
  canMilestone,
  canProject,
  canType,
  setIssueTypeCallback,
  issueTypesEnabled,
}: SharedMetadataProps) => {
  const {optionConfig} = useIssueCreateConfigContext()
  const {repository, labels, setLabels, assignees, setAssignees, projects, setProjects, milestone, issueType} =
    useIssueCreateDataContext()

  const sharedConfigProps = {
    insidePortal: optionConfig.insidePortal,
    shortcutEnabled: optionConfig.singleKeyShortcutsEnabled,
  }

  const firstSelectedProjectTitle = projects[0]?.title || ''

  const pickerProps: AssigneeRepositoryPickerProps | null =
    repository && (canAssign || assignees.length > 0) && !optionConfig.scopedAssignees
      ? {
          repo: repository.name,
          owner: repository.owner.login,
          readonly: !canAssign,
          includeAuthorableBots: false,
          includeAssignableBots: true,
          assignees,
          assigneeTokens: [],
          anchorElement: (anchorProps: React.HTMLAttributes<HTMLElement>, ref: RefObject<HTMLButtonElement>) => (
            <DefaultAssigneePickerAnchor
              assignees={assignees}
              readonly={!canAssign}
              anchorProps={anchorProps}
              ref={ref}
              {...sharedConfigProps}
            />
          ),
          onSelectionChange: setAssignees,
          maximumAssignees: repository.planFeatures.maximumAssignees,
          ...sharedConfigProps,
        }
      : null

  let picker: JSX.Element | null = null
  if (pickerProps) {
    picker = <AssigneeRepositoryPicker {...pickerProps} />
  }

  return (
    <Suspense fallback={<MetadataFooterLoading />}>
      <Box sx={{display: 'flex', flexDirection: 'row', gap: 2, flexWrap: 'wrap'}}>
        {picker}
        {optionConfig.scopedAssignees && (
          <CompressedAssigneeAnchor
            assignees={optionConfig.scopedAssignees}
            displayHotkey={false}
            anchorProps={undefined}
            readonly
          />
        )}
        {(canLabel || labels.length > 0) && (
          <LabelPicker
            repo={repo}
            owner={owner}
            readonly={!canLabel}
            labels={labels}
            anchorElement={(anchorProps, ref) => (
              <DefaultLabelAnchor
                readonly={!canLabel}
                labels={labels}
                anchorProps={anchorProps}
                ref={ref}
                {...sharedConfigProps}
              />
            )}
            onSelectionChanged={setLabels}
            {...sharedConfigProps}
          />
        )}
        {issueTypesEnabled && (canType || issueType !== null) && !optionConfig.scopedIssueType && (
          <IssueTypePicker
            repo={repo}
            owner={owner}
            onSelectionChange={setIssueTypeCallback}
            anchorElement={anchorProps => (
              <DefaultIssueTypePickerFooterAnchor
                readonly={!canType}
                activeIssueType={issueType}
                anchorProps={anchorProps}
                {...sharedConfigProps}
              />
            )}
            readonly={!canType}
            activeIssueType={issueType ?? null}
            width="medium"
            {...sharedConfigProps}
          />
        )}
        {optionConfig.scopedIssueType && (
          <SharedPicker anchorText={optionConfig.scopedIssueType} leadingIcon={IssueOpenedIcon} readonly />
        )}
        {repository && !optionConfig.scopedProjectTitle && (canProject || projects.length > 0) && (
          <ErrorBoundary
            fallback={<SharedPicker anchorText={'Projects are unavailable'} leadingIcon={AlertIcon} readonly />}
          >
            <ProjectPicker
              pickerId="create-issue-projects-picker"
              readonly={!canProject}
              onSave={setProjects}
              selectedProjects={projects}
              firstSelectedProjectTitle={firstSelectedProjectTitle}
              owner={repository.owner.login}
              repo={repository.name}
              anchorElement={anchorProps => (
                <DefaultProjectPickerAnchor
                  nested={false}
                  readonly={!canMilestone}
                  anchorProps={anchorProps}
                  firstSelectedProjectTitle={firstSelectedProjectTitle}
                  {...sharedConfigProps}
                />
              )}
              {...sharedConfigProps}
            />
          </ErrorBoundary>
        )}
        {/* Rendered when created from a Memex project */}
        {optionConfig.scopedProjectTitle && (
          <SharedPicker anchorText={optionConfig.scopedProjectTitle} leadingIcon={TableIcon} readonly />
        )}
        {(canMilestone || milestone !== null) && !optionConfig.scopedMilestone && (
          <MilestonePicker
            repo={repo}
            owner={owner}
            readonly={!canMilestone}
            activeMilestone={milestone}
            anchorElement={(anchorProps, ref) => (
              <DefaultMilestonePickerAnchor
                nested={false}
                readonly={!canMilestone}
                activeMilestone={milestone}
                anchorProps={anchorProps}
                ref={ref}
                {...sharedConfigProps}
              />
            )}
            onSelectionChanged={setMilestoneCallback}
            {...sharedConfigProps}
          />
        )}
        {optionConfig.scopedMilestone && (
          <SharedPicker anchorText={optionConfig.scopedMilestone} leadingIcon={MilestoneIcon} readonly />
        )}
      </Box>
    </Suspense>
  )
}
