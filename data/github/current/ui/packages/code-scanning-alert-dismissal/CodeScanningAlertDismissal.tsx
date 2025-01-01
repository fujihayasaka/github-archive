// Give a surrounding element a class of `js-alert-actions-portal-root` to render the overlay in that element.
// This will no longer be required once https://github.com/primer/react/issues/4694 has been done
import {
  AnchoredOverlay,
  ActionList,
  Heading,
  IconButton,
  Button,
  Flash,
  FormControl,
  RadioGroup,
  Radio,
  Textarea,
  registerPortalRoot,
  type OverlayProps,
} from '@primer/react'
import {TriangleDownIcon, XIcon} from '@primer/octicons-react'

import {useEffect, useState} from 'react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import styles from './CodeScanningAlertDismissal.module.css'

import {clsx} from 'clsx'

export interface CodeScanningAlertDismissalProps {
  alertClosureReasons: {[key: string]: string}
  closeReasonDetails: {[key: string]: string}
  path: string
  buttonLabel: string
  hasPendingRequest: boolean
  number?: number
  refNames?: string[]
  reloadPage?: boolean
  prReviewThreadID?: number
  delegatedAlertDismissalEnabled: boolean
}

export function CodeScanningAlertDismissal({
  alertClosureReasons,
  closeReasonDetails,
  number,
  path,
  buttonLabel,
  hasPendingRequest,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  refNames = [],
  prReviewThreadID,
  delegatedAlertDismissalEnabled,
}: CodeScanningAlertDismissalProps) {
  const [open, setOpen] = useState(false)
  const [reason, setReason] = useState('')
  const [portalRoot, setPortalRoot] = useState<string | null>(null)

  const handleReasonChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setReason(event.target.value)
  }

  useEffect(() => {
    const root = document.querySelector('.js-alert-actions-portal-root')
    if (root) {
      registerPortalRoot(root, 'alert-actions-portal-root')
      setPortalRoot('alert-actions-portal-root')
    }
  }, [])

  const closeOverlay = () => {
    setOpen(false)
    setReason('')
    setDismissalComment('')
    setError(false)
  }

  const [dismissalComment, setDismissalComment] = useState('')
  const handleSetReason = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setDismissalComment(e.target.value)
  }

  const [error, setError] = useState(false)
  const [commentValidationError, setCommentValidationError] = useState(false)
  const [reasonValidationError, setReasonValidationError] = useState(false)

  const handleSubmit = async (e: React.FormEvent<EventTarget>) => {
    e.preventDefault()
    const commentIsMissing = delegatedAlertDismissalEnabled && dismissalComment.trim() === ''
    const reasonIsMissing = !reason

    setCommentValidationError(commentIsMissing)
    setReasonValidationError(reasonIsMissing)

    if (commentIsMissing || reasonIsMissing) {
      return
    }

    const formData = new FormData()
    formData.set('_method', 'put')
    formData.set('reason', reason)
    formData.set('resolution_note', dismissalComment)
    if (number) {
      formData.append('number[]', number.toString())
    }
    for (const ref_name of refNames) {
      formData.append('ref_names_b64[]', ref_name)
    }

    if (prReviewThreadID) {
      formData.set('pull_request_review_thread', prReviewThreadID.toString())
    }

    const result = await verifiedFetch(path, {
      method: 'POST',
      body: formData,
    })

    if (!result.ok) {
      setError(true)
    } else {
      closeOverlay()
      window.location.reload()
    }
  }

  const anchorLabel = hasPendingRequest ? 'Request pending' : buttonLabel
  const overlayProps: Partial<OverlayProps> = {
    role: 'dialog',
    'aria-modal': 'true',
    className: 'd-flex flex-1 overflow-hidden',
  }
  if (portalRoot) {
    overlayProps.portalContainerName = portalRoot
  }

  return (
    <AnchoredOverlay
      open={open}
      onOpen={() => setOpen(true)}
      onClose={closeOverlay}
      width="medium"
      height="fit-content"
      focusZoneSettings={{disabled: true}}
      renderAnchor={props => (
        <Button
          {...props}
          size="small"
          trailingVisual={hasPendingRequest ? null : TriangleDownIcon}
          data-testid="code-scanning-alert-dismissal-toggle-button"
          disabled={hasPendingRequest}
        >
          {anchorLabel}
        </Button>
      )}
      overlayProps={overlayProps}
    >
      <form
        onSubmit={handleSubmit}
        data-testid="code-scanning-alert-dismissal-form"
        className="d-flex flex-1 flex-column"
      >
        <div className="py-1 px-2 d-flex borderColor-muted border-bottom flex-items-center">
          <Heading as="h2" className="flex-1 f6" id="dismissal_reason">
            Select a reason to dismiss
          </Heading>
          {/*
            We don't need unsafeDisableTooltip since this IconButton is ready for its
            tooltip to be shown. cf https://github.com/github/github/pull/331875
            This comment block can be removed once step 2 of this plan is complete:
            https://github.com/github/primer/discussions/3333
          */}
          <IconButton
            icon={XIcon}
            size="small"
            aria-label="Close"
            variant="invisible"
            onClick={closeOverlay}
            tooltipDirection="sw"
          />
        </div>
        <div className="flex-1 overflow-y-auto py-2">
          <RadioGroup
            name={'Alert Dismissal Reasons'}
            aria-labelledby="dismissal_reason"
            className={styles.DismissalRadioContainer}
          >
            {Object.entries(alertClosureReasons).map(([key, value], index) => (
              <div key={key} data-testid="code-scanning-alert-dismissal-reason">
                <FormControl className={styles.DismissalFormControl}>
                  <Radio
                    name="reason"
                    value={key}
                    onChange={handleReasonChange}
                    className={styles.DismissalRadioOption}
                  />
                  <FormControl.Label className={styles.DismissalFormLabel}>{value}</FormControl.Label>
                  <FormControl.Caption className={styles.DismissalFormCaption}>
                    {closeReasonDetails[key]}
                  </FormControl.Caption>
                </FormControl>
                {index !== Object.keys(alertClosureReasons).length - 1 && <ActionList.Divider />}
              </div>
            ))}
          </RadioGroup>
          {reasonValidationError && (
            <div className="px-3 mb-1 fgColor-danger">
              <FormControl.Validation variant="error">Please select a dismissal reason</FormControl.Validation>
            </div>
          )}

          <FormControl>
            <FormControl.Label required={delegatedAlertDismissalEnabled} className={styles.DismissalReasonLabel}>
              Dismissal Reason
            </FormControl.Label>
            <div className="px-3 full-width" data-testid="code-scanning-alert-dismissal-comment">
              <Textarea
                aria-label="Dismissal Reason"
                rows={2}
                className={clsx('mb-2 d-block', styles.DismissalFormLabel)}
                onChange={handleSetReason}
                value={dismissalComment}
                maxLength={280}
                placeholder="Add a comment"
                data-testid="code-scanning-alert-dismissal-comment-textarea"
              />
              {commentValidationError && (
                <FormControl.Validation variant="error" className={styles.DismissalValidationMessage}>
                  This field is required
                </FormControl.Validation>
              )}
            </div>
          </FormControl>
        </div>
        <div className="borderColor-muted border-top">
          {error && (
            <Flash variant="danger" className="mx-2 mt-2">
              There was an issue dismissing the alert(s). Please try again.
            </Flash>
          )}
          <div className="d-flex flex-justify-end p-3">
            <Button onClick={closeOverlay} className="mr-2">
              Cancel
            </Button>
            <Button variant="primary" type="submit" data-testid="code-scanning-alert-dismissal-submit-button">
              {buttonLabel}
            </Button>
          </div>
        </div>
      </form>
    </AnchoredOverlay>
  )
}
