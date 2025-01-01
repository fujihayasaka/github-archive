import {Blankslate} from '@primer/react/experimental'
import type {RequestType} from '../delegated-bypass-types'

type BypassRequestsBlankProps = {
  requestType: RequestType
}

export function BypassRequestsBlank({requestType}: BypassRequestsBlankProps) {
  const requestTypeLabel = requestType === 'secret_scanning_closure' ? 'alert dismissal' : 'bypass'
  return (
    <Blankslate>
      <Blankslate.Heading>{`No ${requestTypeLabel} requests found`}</Blankslate.Heading>
      <Blankslate.Description>Try adjusting the filters to refine your search.</Blankslate.Description>
    </Blankslate>
  )
}
