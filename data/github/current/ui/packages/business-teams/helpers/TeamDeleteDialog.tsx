import React from 'react'
import {Dialog} from '@primer/react/experimental'
import {Button} from '@primer/react'
import {LightBulbIcon} from '@primer/octicons-react'

interface TeamDeleteDialogProps {
  isOpen: boolean
  onClose: () => void
  onConfirm: () => void
  selectedTeams: Set<string>
}

const TeamDeleteDialog: React.FC<TeamDeleteDialogProps> = ({isOpen, onClose, onConfirm, selectedTeams}) => {
  const buttonRef = React.useRef<HTMLButtonElement>(null)

  return (
    <>
      {isOpen && (
        <Dialog
          title="Delete team"
          subtitle="You’re about to delete the following teams:"
          onClose={() => onClose()}
          position={{narrow: 'bottom', regular: 'center'}}
          returnFocusRef={buttonRef}
        >
          <div className="mb-3">
            <strong>{Array.from(selectedTeams).join(', ')}</strong>
          </div>
          <div className="mb-3 font-size-1 text-muted">
            <LightBulbIcon /> Team restoration is possible for 90 days post-deletion.
          </div>
          <Dialog.Footer>
            <Button variant="default" onClick={onClose}>
              Cancel
            </Button>
            <Button data-testid="confirmation-dialog-delete" variant="danger" onClick={onConfirm}>
              Delete team
            </Button>
          </Dialog.Footer>
        </Dialog>
      )}
    </>
  )
}

export default TeamDeleteDialog
