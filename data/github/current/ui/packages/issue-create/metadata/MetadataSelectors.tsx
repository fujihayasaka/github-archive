import {useCallback} from 'react'
import {useIssueCreateDataContext} from '../contexts/IssueCreateDataContext'
import {useIssueCreateConfigContext} from '../contexts/IssueCreateConfigContext'
import type {Milestone} from '@github-ui/item-picker/MilestonePicker'
import {MetadataFooter} from './MetadataFooter'
import {MetadataSidebar} from './MetadataSidebar'
import type {IssueType} from '@github-ui/item-picker/IssueTypePicker'

export type SharedMetadataProps = {
  repo: string
  owner: string
  setMilestoneCallback: (milestones: Milestone[] | null) => void
  setIssueTypeCallback: (types: IssueType[] | null) => void
  canAssign: boolean
  canLabel: boolean
  canMilestone: boolean
  canProject: boolean
  canType: boolean
  issueTypesEnabled: boolean
}

export const MetadataSelectors = () => {
  const {optionConfig} = useIssueCreateConfigContext()
  const showMetadataInSidebar = !optionConfig.insidePortal
  const {repository, setMilestone, setIssueType} = useIssueCreateDataContext()

  const setMilestoneCallback = useCallback(
    (milestones: Milestone[] | null) => {
      setMilestone(milestones?.[0] || null)
    },
    [setMilestone],
  )

  const setIssueTypeCallback = useCallback(
    (types: IssueType[] | null) => {
      setIssueType(types?.[0] || null)
    },
    [setIssueType],
  )

  const canAssign = repository?.viewerIssueCreationPermissions?.assignable
  const canLabel = repository?.viewerIssueCreationPermissions?.labelable
  const canMilestone = repository?.viewerIssueCreationPermissions?.milestoneable
  const canProject = repository?.viewerIssueCreationPermissions?.triageable
  const canType = repository?.viewerIssueCreationPermissions?.typeable
  const issueTypesEnabled = repository?.owner?.issueTypesEnabled

  const sharedMetadataProps: SharedMetadataProps = {
    repo: repository?.name || '',
    owner: repository?.owner.login || '',
    setMilestoneCallback,
    setIssueTypeCallback,
    canAssign: canAssign ?? false,
    canLabel: canLabel ?? false,
    canMilestone: canMilestone ?? false,
    canProject: canProject ?? false,
    canType: canType ?? false,
    issueTypesEnabled: issueTypesEnabled ?? false,
  }

  return showMetadataInSidebar ? (
    <MetadataSidebar {...sharedMetadataProps} />
  ) : (
    <MetadataFooter {...sharedMetadataProps} />
  )
}
