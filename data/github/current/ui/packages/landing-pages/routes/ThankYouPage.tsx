import {useEffect} from 'react'
import {trackContactSalesEvent} from '@github-ui/microsoft-analytics/events'

import {ShowPage} from './ShowPage'

export const ThankYouPage = () => {
  useEffect(() => {
    const queryParams = new URLSearchParams(window.location.search)
    const utmContent = queryParams.get('utm_content')
    const refId = queryParams.get('ref_id')
    const timestamp = Date.now()

    if (utmContent && refId) {
      trackContactSalesEvent({
        productTitle: utmContent,
        orderId: `${refId}-${utmContent}-${timestamp}`,
      })
    }
  }, [])

  return <ShowPage />
}
