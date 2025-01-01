import {ssrSafeDocument, ssrSafeWindow} from '@github-ui/ssr-utils'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {useCallback, useEffect, useState} from 'react'
import type {UpsellData} from './types'

export const useFetchUpsellData = () => {
  const [data, setData] = useState<UpsellData>()

  useEffect(() => {
    const fetchData = async () => {
      try {
        const response = await reactFetchJSON(`${ssrSafeWindow?.location.pathname}/copilot_code_review_show_upsell`, {
          method: 'GET',
        })
        if (!response.ok) throw new Error()
        const body = await response.json()
        setData(body)
      } catch {
        // fail silently, nothing the user can do to fix it
      }
    }
    fetchData()
  }, [])

  return data
}

// determine if we should display the upsell dialog on reviewer selection
export const useShowUpsellDialog = () => {
  const [showUpsell, setShowUpsell] = useState(false)

  // listen for reviewer selections and check if they're ccr-quota-limited
  useEffect(() => {
    const menu = ssrSafeDocument?.getElementById('reviewers-select-menu')

    const listener = (e: Event) => {
      const target = e.target as HTMLElement | null

      if (
        !target ||
        !target.getAttribute('data-ccr-quota-limited') || // only check ccr-limited elements
        target.parentElement?.getAttribute('aria-checked') === 'true' // let users de-select the reviewer
      ) {
        return
      }

      e.preventDefault()
      e.stopPropagation()
      setShowUpsell(true)
      menu?.removeAttribute('open')
    }

    menu?.addEventListener('click', listener)
    return () => menu?.removeEventListener('click', listener)
  }, [])

  return [showUpsell, setShowUpsell] as const
}

export const useDismissUpsellBanner = (key?: string) => {
  const [isDismissed, setDismissed] = useState(false)
  const container = ssrSafeDocument?.getElementById('copilot-code-review-limits-banner')

  const handleDismiss = useCallback(() => {
    setDismissed(true)
    try {
      reactFetchJSON(`${ssrSafeDocument?.location.pathname}/copilot_code_review_dismiss_upsell`, {
        method: 'POST',
        body: {key},
      })
    } catch {
      // fail silently, nothing the user can do to fix it
    }
  }, [key])

  return {container, isDismissed, handleDismiss}
}
