import type {CodeScanningDevelopmentPickerProps} from '../CodeScanningDevelopmentPicker'

export function getCodeScanningDevelopmentPickerProps(): CodeScanningDevelopmentPickerProps {
  return {
    repositoryNwo: 'owner/repo',
    repositoryId: 1,
    alertNumber: 1,
    linkedBranches: [],
    linkedPullRequests: [],
    isCreateBranchDialogOpen: false,
    updateAlertLinksPath: '/update/alert/links/path',
  }
}
