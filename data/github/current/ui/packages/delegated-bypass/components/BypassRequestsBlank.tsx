import {Blankslate} from '@primer/react/experimental'
import type {RequestType} from '../delegated-bypass-types'

type BypassRequestsBlankProps = {
  requestType: RequestType
  unauthorizedUser?: boolean
}

export function BypassRequestsBlank({requestType, unauthorizedUser}: BypassRequestsBlankProps) {
  const requestTypeLabel =
    requestType === 'secret_scanning_closure' || requestType === 'code_scanning_alert_dismissal'
      ? 'alert dismissal'
      : 'bypass'
  let requestTypeDescription = 'Try adjusting the filters to refine your search.'
  if (unauthorizedUser) {
    requestTypeDescription = `You must be an enterprise owner to view ${requestTypeLabel} requests.`
  }

  return (
    <Blankslate>
      <Blankslate.Heading>{`No ${requestTypeLabel} requests found`}</Blankslate.Heading>
      <Blankslate.Description>{requestTypeDescription}</Blankslate.Description>
    </Blankslate>
  )
}
