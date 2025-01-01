import {Link} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import type {PendingCycleChange} from '../types/pending-cycle-change'
import {ClockIcon} from '@primer/octicons-react'
import {format} from 'date-fns'
import {clsx} from 'clsx'
import styles from './PendingPlanChange.module.css'
import {useState} from 'react'
import {useNavigation} from '../contexts/NavigationContext'

export interface PendingPlanChangeProps {
  onCancelConfirmed: () => void
  pendingChange: PendingCycleChange
}
export function PendingPlanChange({onCancelConfirmed, pendingChange}: PendingPlanChangeProps) {
  const {isStafftools} = useNavigation()
  const {changeType, effectiveDate, isChangingSeats, newPrice, newSeatCount, planDisplayName, planDuration} =
    pendingChange

  const [isConfirmCancelDialogOpen, setIsConfirmCancelDialogOpen] = useState<boolean>(false)

  const onCancelClick = (event: React.MouseEvent<HTMLAnchorElement>) => {
    event.preventDefault()
    setIsConfirmCancelDialogOpen(true)
  }
  const onCancelConfirmDialogClose = () => {
    setIsConfirmCancelDialogOpen(false)
  }
  const onCancelOkClick = () => {
    setIsConfirmCancelDialogOpen(false)
    onCancelConfirmed()
  }

  const pendingChangeText = pendingChange.isCancellation
    ? 'Your cancellation'
    : `Your ${changeType} to ${planDisplayName} plan ${
        isChangingSeats ? `with ${newSeatCount.toLocaleString()} licenses` : ''
      }`

  return (
    <>
      <div className="d-flex flex-items-center">
        <div className="flex-self-center pr-3">
          <ClockIcon size={16} className="fgColor-attention" />
        </div>
        <div className="flex-auto text-small">
          <div className="my-1" data-testid="pending-plan-change">
            {pendingChangeText} will be effective on <strong>{format(effectiveDate, 'MMMM d, yyyy')}</strong>.
            <br />
            The new price will be <strong>{newPrice}</strong> / {planDuration}.{' '}
            {!isStafftools && (
              <Link
                href="#"
                className={clsx('d-inline-block', 'mx-2', 'fgColor-default', 'text-semibold', styles.cancelButton)}
                onClick={onCancelClick}
                data-testid="cancel-pending-plan-change-button"
              >
                Cancel
              </Link>
            )}
          </div>
        </div>
        <strong className="flex-self-center f5">{newPrice}</strong>
      </div>
      {isConfirmCancelDialogOpen && (
        <Dialog
          title="Cancel pending plan change"
          onClose={onCancelConfirmDialogClose}
          width="medium"
          footerButtons={[
            {
              content: <span data-testid="confirm-dialog-cancel-button">Close</span>,
              onClick: onCancelConfirmDialogClose,
            },
            {
              autoFocus: true,
              content: <span data-testid="confirm-dialog-confirm-button">Confirm cancellation</span>,
              buttonType: 'danger',
              onClick: onCancelOkClick,
            },
          ]}
        >
          Are you sure you want to cancel this pending plan change? Cancelling the pending changes will revert back to
          your original plan.
        </Dialog>
      )}
    </>
  )
}
