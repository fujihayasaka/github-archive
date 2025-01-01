import {XIcon} from '@primer/octicons-react'
import {Dialog} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {format} from 'date-fns'

export interface CancelSubscriptionDialogProps {
  expiration: string
  isCanceling: boolean
  onConfirmed: () => void
  onClose: () => void
}

export function CancelSubscriptionDialog({
  expiration,
  isCanceling,
  onConfirmed,
  onClose,
}: CancelSubscriptionDialogProps) {
  return (
    <Dialog
      title="Cancel GitHub Advanced Security"
      onClose={onClose}
      footerButtons={[
        {
          buttonType: 'danger',
          disabled: isCanceling,
          onClick: onConfirmed,
          content: isCanceling ? 'Submitting request' : 'I understand, cancel Advanced Security',
        },
      ]}
      renderBody={() => (
        <Dialog.Body>
          <Banner variant="warning" title="Are you sure you want to cancel GitHub Advanced Security?" />
          <p className="mt-2">You will lose access to these benefits:</p>
          <ul className="list-style-none">
            <li className="mb-2">
              <XIcon size="small" className="fgColor-danger" />
              See security issues as part of your code review process.
            </li>
            <li className="mb-2">
              <XIcon size="small" className="fgColor-danger" />
              Prevent secrets being committed as code.
            </li>
            <li className="mb-2">
              <XIcon size="small" className="fgColor-danger" />
              Create queries to find and prevent variants of new security concerns.
            </li>
          </ul>
          <p>
            If cancelled, your access to GitHub Advanced Security will expire on {format(expiration, 'MMMM d, yyyy')}.
            You will not be billed going forward.
          </p>
        </Dialog.Body>
      )}
      role="dialog"
    />
  )
}
