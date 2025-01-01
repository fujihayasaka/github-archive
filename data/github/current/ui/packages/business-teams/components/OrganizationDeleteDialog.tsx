import React from 'react'
import {Dialog} from '@primer/react/experimental'
import {Button} from '@primer/react'
import pluralize from 'pluralize'
import type {Organization} from '../types'
import {GitHubAvatar} from '@github-ui/github-avatar'
import styles from '../styles/OrganizationDeleteDialog.module.css'

interface OrganizationDeleteDialogProps {
  isOpen: boolean
  onClose: () => void
  onConfirm: () => void
  selectedOrganizations: Organization[]
  teamName: string
}

const OrganizationDeleteDialog: React.FC<OrganizationDeleteDialogProps> = ({
  isOpen,
  onClose,
  onConfirm,
  selectedOrganizations,
  teamName,
}) => {
  const buttonRef = React.useRef<HTMLButtonElement>(null)

  return (
    <>
      {isOpen && (
        <Dialog
          title={`Remove ${pluralize('organization', selectedOrganizations.length)}`}
          onClose={() => onClose()}
          position={{narrow: 'bottom', regular: 'center'}}
          returnFocusRef={buttonRef}
        >
          <p className="mb-2" data-testid="remove-orgs-dialog-header">
            You&apos;re about to remove the <strong>{teamName}</strong> team from{' '}
            <strong>
              {selectedOrganizations.length} {pluralize('organization', selectedOrganizations.length)}
            </strong>
            .
          </p>
          <div className={styles.orgs}>
            {selectedOrganizations.map(org => (
              <div key={org.name} className={styles.org}>
                <div className="mr-2">
                  <GitHubAvatar size={20} src={org.avatarUrl} alt="User avatar" />
                </div>
                <div>
                  <strong data-testid={`remove-orgs-dialog-org-login-${org.id}`}>{org.name || org.login}</strong>
                </div>
              </div>
            ))}
          </div>
          <p className="mt-2 mb-3" data-testid="remove-orgs-dialog-impact-description">
            Members of the team might lose permissions to the removed organizations and their repositories.
          </p>
          <Dialog.Footer>
            <Button variant="default" onClick={onClose}>
              Cancel
            </Button>
            <Button data-testid="confirmation-dialog-delete" variant="danger" onClick={onConfirm}>
              Remove {pluralize('organization', selectedOrganizations.length)}
            </Button>
          </Dialog.Footer>
        </Dialog>
      )}
    </>
  )
}

export default OrganizationDeleteDialog
