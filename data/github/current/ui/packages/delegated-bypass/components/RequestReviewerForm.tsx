import {Button, FormControl, Textarea} from '@primer/react'
import {useEffect, useState} from 'react'
import type {ExemptionRequest, UpdateStatus} from '../delegated-bypass-types'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useSearchParams} from '@github-ui/use-navigate'
import {updateExemptionRequest} from '../services/api'
import {useDelegatedBypassSetBanner} from '../contexts/DelegatedBypassBannerContext'
import {useRequestTypeContext} from '../contexts/RequestTypeContext'
import {componentRegistry} from './RequestForm'
import {UpdateState} from '../helpers/constants'
import {updateBanner} from '../helpers/banner'

export function RequestReviewerForm({
  request,
  hasPostApprovalAction,
  postApprovalRedirectUrl,
}: {
  request: ExemptionRequest
  hasPostApprovalAction: boolean
  postApprovalRedirectUrl?: string
}) {
  const {requester} = request
  const [message, setMessage] = useState('')
  const [messageError, setMessageError] = useState('')
  const [updateState, setUpdateState] = useState<UpdateState>(UpdateState.Initial)
  const [status, setStatus] = useState<UpdateStatus>()
  const [, setSearchParams] = useSearchParams()
  const setBanner = useDelegatedBypassSetBanner()
  const requestType = useRequestTypeContext()

  const {FormControls, ReviewerWarning} = componentRegistry({requestType, hasPostApprovalAction})

  useEffect(() => {
    updateBanner(updateState, setBanner, setSearchParams, 'submitted', 'submitting')
  }, [updateState, setBanner, setSearchParams])

  function validateMessage(comment: string) {
    if (requestType === 'secret_scanning') {
      if (comment.trim() === '') {
        setMessageError('A comment is required')
        return true
      }
      if (comment.trim().length > 2048) {
        setMessageError('Comment is too long')
        return true
      }
    }
    setMessageError('')
    return false
  }

  return (
    <div className="Box mt-4">
      <div className="mx-4 mt-4 mb-0 d-flex flex-column">
        {ReviewerWarning ? (
          <ReviewerWarning />
        ) : (
          <>
            <span className="f-3 text-bold mb-1">{hasPostApprovalAction ? 'Execute' : 'Approve'} bypass request</span>
            {hasPostApprovalAction ? (
              <span>
                As an approver, you may approve and execute <b>{requester.login}</b>&apos;s request.
              </span>
            ) : (
              <span>
                As an approver, you may allow <b>{requester.login}</b> to bypass these push protections
                {requestType === 'secret_scanning' && ' and expose any detected secrets.'}
              </span>
            )}
          </>
        )}
      </div>
      {FormControls ? (
        <div className="m-4 d-flex flex-column">
          <FormControls />
        </div>
      ) : null}
      <form
        className="m-4"
        method="put"
        action={ssrSafeLocation.pathname}
        noValidate
        onSubmit={async e => {
          setUpdateState(UpdateState.Submitting)
          e.preventDefault()
          if (validateMessage(message)) {
            setUpdateState(UpdateState.Error)
            return
          }
          const response = await updateExemptionRequest(ssrSafeLocation.pathname, {status, message})
          if (response.statusCode === 201) {
            if (postApprovalRedirectUrl && status === 'approve') {
              setUpdateState(UpdateState.Redirecting)
              setTimeout(() => {
                // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
                window.location.href = postApprovalRedirectUrl!
              }, 3000)
            } else {
              setUpdateState(UpdateState.Success)
            }
          } else {
            setUpdateState(UpdateState.Error)
          }
        }}
      >
        {requestType === 'secret_scanning' && (
          <FormControl>
            <FormControl.Label required>Add a comment</FormControl.Label>
            <Textarea
              block
              rows={5}
              placeholder="Type your comment here..."
              value={message}
              onBlur={e => validateMessage(e.target.value)}
              onChange={e => {
                setMessage(e.target.value)
                setMessageError('')
                validateMessage(e.target.value)
              }}
            />
            {messageError && <FormControl.Validation variant="error">{messageError}</FormControl.Validation>}
          </FormControl>
        )}
        <div className="d-flex mt-4 gap-3">
          <Button
            type="submit"
            className="flex-1"
            variant="danger"
            size="large"
            disabled={updateState === UpdateState.Submitting}
            onClick={() => setStatus('reject')}
          >
            Deny request
          </Button>
          <Button
            type="submit"
            className="flex-1"
            size="large"
            disabled={updateState === UpdateState.Submitting}
            onClick={() => setStatus('approve')}
          >
            Approve request
          </Button>
        </div>
      </form>
    </div>
  )
}
