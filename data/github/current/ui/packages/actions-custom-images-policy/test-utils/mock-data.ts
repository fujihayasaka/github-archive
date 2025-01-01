import type {ActionsCustomImagesPolicyProps} from '../ActionsCustomImagesPolicy'
import type {OrgSelectionDialogProps} from '../OrgSelectionDialog'
import {AccessPolicy} from '../types'

export function getActionsCustomImagesPolicyProps(): ActionsCustomImagesPolicyProps {
  return {
    accessPolicy: AccessPolicy.None,
    action: 'path/to/custom-images-policy',
    bulkOrgAction: 'path/to/bulk-org-action',
    orgs: [
      {id: 1, name: 'org1', selected: false},
      {id: 2, name: 'org2', selected: true},
      {id: 3, name: 'org3', selected: false},
    ],
  }
}

export function getOrgSelectionDialogProps(): OrgSelectionDialogProps {
  return {
    action: 'path/to/org-selection-action',
    organizations: [
      {id: 1, name: 'org1', selected: false},
      {id: 2, name: 'org2', selected: true},
      {id: 3, name: 'org3', selected: false},
    ],
    closeDialog: jest.fn(),
  }
}
