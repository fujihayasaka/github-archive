import React from 'react'
import {Dialog} from '@primer/react/experimental'
import type {User} from '../types'
import {GitHubAvatar} from '@github-ui/github-avatar'
import pluralize from 'pluralize'
import styles from '../styles/RemoveMembersDialog.module.css'

interface RemoveMembersDialogProps {
  isOpen: boolean
  onClose: () => void
  onConfirm: () => void
  teamName: string
  members: User[]
}

const RemoveMembersDialog: React.FC<RemoveMembersDialogProps> = ({isOpen, onClose, onConfirm, teamName, members}) => {
  const buttonRef = React.useRef<HTMLButtonElement>(null)
  const memberCount = members.length
  const memberText = pluralize('member', memberCount)

  return (
    <>
      {isOpen && (
        <Dialog
          title={`Remove ${memberText}`}
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
              content: `Remove ${memberText}`,
              onClick: () => onConfirm(),
              ref: buttonRef,
            },
          ]}
        >
          <p className="mb-2" data-testid="remove-members-dialog-description">
            You&apos;re about to remove{' '}
            <strong>
              {memberCount} {memberText}
            </strong>{' '}
            from the <strong>{teamName}</strong> team.
          </p>
          {memberCount > 1 && (
            <p
              data-testid="remove-members-dialog-list-description"
              className={`text-small ${styles.secondaryTextColor}`}
            >
              The following members will be removed from the team:
            </p>
          )}
          <div className={styles.members}>
            {members.map(member => (
              <div key={member.displayLogin} className={styles.member}>
                <div className="mr-2">
                  <GitHubAvatar size={20} src={member.avatarUrl} alt="User avatar" />
                </div>
                <div>
                  <strong data-testid={`remove-members-dialog-member-login-${member.id}`}>{member.displayLogin}</strong>
                  <span
                    className={`ml-2 ${styles.secondaryTextColor}`}
                    data-testid={`remove-members-dialog-member-name-${member.id}`}
                  >
                    {member.profileName}
                  </span>
                </div>
              </div>
            ))}
          </div>
          <p className={`mt-2 mb-0 ${styles.smallMutedText}`} data-testid="remove-members-dialog-impact-description">
            Removed {memberText} might lose permissions to organizations or repositories.
          </p>
        </Dialog>
      )}
    </>
  )
}

export default RemoveMembersDialog
