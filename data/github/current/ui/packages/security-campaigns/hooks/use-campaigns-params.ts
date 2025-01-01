import {useSearchParams} from '@github-ui/use-navigate'
import {useCallback, useState} from 'react'
import {parseSecurityCampaignState, type SecurityCampaignState} from '../types/security-campaign-state'
import {parseCursor, serializeCursor, type Cursor} from '../types/cursor'

export function useCampaignsParams() {
  const [params, setParams] = useSearchParams()
  const [campaignState, setCampaignState] = useState<SecurityCampaignState>(() =>
    parseSecurityCampaignState(params.get('state')),
  )
  const [cursor, setCursor] = useState<Cursor | null>(() => parseCursor(params))

  // Changing the state also resets the cursor.
  // Calling setParams twice in one render doesn't appear to work correctly so we need to do it in a single call.
  const onCampaignStateChange = useCallback(
    (newState: SecurityCampaignState) => {
      setCampaignState(newState)
      setCursor(null)
      setParams(prevParams => {
        const next = new URLSearchParams(prevParams)
        next.set('state', newState)
        next.delete('before')
        next.delete('after')
        return next
      })
    },
    [setParams],
  )

  const onCursorChange = useCallback(
    (newCursor: Cursor | null) => {
      setCursor(newCursor)
      setParams(prevParams => {
        const next = new URLSearchParams(prevParams)
        serializeCursor(newCursor, next)
        return next
      })
    },
    [setParams],
  )

  return {
    campaignState,
    cursor,
    onCampaignStateChange,
    onCursorChange,
  }
}
