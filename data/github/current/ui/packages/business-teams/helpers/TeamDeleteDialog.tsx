import React from 'react'
import {Dialog} from '@primer/react/experimental'
import pluralize from 'pluralize'
import styles from '../styles/TeamDeleteDialog.module.css'

interface TeamDeleteDialogProps {
  isOpen: boolean
  onClose: () => void
  onConfirm: () => void
  selectedTeams: Set<{slug: string; name: string}>
}

const TeamDeleteDialog: React.FC<TeamDeleteDialogProps> = ({isOpen, onClose, onConfirm, selectedTeams}) => {
  const buttonRef = React.useRef<HTMLButtonElement>(null)

  return (
    <>
      {isOpen && (
        <Dialog
          title={`Delete ${pluralize('team', selectedTeams.size)}`}
          onClose={() => onClose()}
          position={{narrow: 'bottom', regular: 'center'}}
          width="large"
          returnFocusRef={buttonRef}
          footerButtons={[
            {
              buttonType: 'default',
              content: 'Cancel',
              onClick: () => onClose(),
              ref: buttonRef,
            },
            {
              buttonType: 'danger',
              content: `Delete ${pluralize('team', selectedTeams.size)}`,
              onClick: () => onConfirm(),
              ref: buttonRef,
            },
          ]}
        >
          <p className="mb-2" data-testid="delete-team-description">
            You&apos;re about to delete{' '}
            <strong>
              {selectedTeams.size} enterprise {pluralize('team', selectedTeams.size)}
            </strong>
            .
          </p>
          <div className={styles.teams}>
            {Array.from(selectedTeams).map(team => (
              <div key={team.slug} className={styles.team}>
                <div>
                  {/* TODO: add team icon when it has been implemented  */}
                  <strong data-testid={`remove-teams-dialog-${team.slug}`}>{team.name}</strong>
                  {/* TODO: add @mentions when it has been implemented*/}
                </div>
              </div>
            ))}
          </div>
          {selectedTeams.size === 1 ? (
            <p className={`mt-2 mb-0 ${styles.smallMutedText}`} data-testid="remove-one-team-dialog-impact-description">
              This action cannot be undone and will remove this team&apos;s configuration, including its membership list
              and permission settings. Any access grants through the team will also be removed.
            </p>
          ) : (
            <p className={`mt-2 mb-0 ${styles.smallMutedText}`}>
              This action cannot be undone and will remove the selected teams&apos; configurations, including their
              membership lists and permission settings. Any access granted through these teams will also be removed.
            </p>
          )}
        </Dialog>
      )}
    </>
  )
}
export default TeamDeleteDialog
