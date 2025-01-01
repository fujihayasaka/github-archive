import {verifiedFetch} from '@github-ui/verified-fetch'
import {useEffect, useMemo, useRef, useState} from 'react'
import {CopilotSummarizeBannerPlaceholder} from './CopilotSummarizeBannerPlaceholder'

export interface CopilotSummarizeBannerLoaderProps {
  /*
   * A relative URL like `/:user_id/:repository/issues/:id/copilot-summaries-banner` to asynchronously load the
   * Copilot summary banner for the content being shown on the page.
   */
  bannerPath: string
}

export function CopilotSummarizeBannerLoader({bannerPath}: CopilotSummarizeBannerLoaderProps) {
  const [bannerHtml, setBannerHtml] = useState<string | null>(null)
  const shouldLoadBanner = bannerPath.length > 0
  const isLoadingRef = useRef(false)
  const [showPlaceholder, setShowPlaceholder] = useState(true)
  const hasBannerHtml = bannerHtml !== null

  useEffect(() => {
    if (hasBannerHtml) return // Banner has already been loaded
    if (!shouldLoadBanner) return
    if (isLoadingRef.current) return // Don't start loading the banner again if we're already loading it
    let current = true

    const loadBanner = async () => {
      isLoadingRef.current = true
      const response = await verifiedFetch(bannerPath, {method: 'GET', headers: {Accept: 'text/html'}})
      if (current && response.ok) {
        const newBannerHtml = await response.text()
        setBannerHtml(newBannerHtml)
      }
    }

    void loadBanner()

    return () => {
      if (current) isLoadingRef.current = false
      current = false
    }
  }, [hasBannerHtml, bannerPath, shouldLoadBanner])

  const shouldRenderBanner = typeof bannerHtml === 'string' && shouldLoadBanner

  useEffect(() => {
    if (shouldRenderBanner) {
      setShowPlaceholder(false)
    }
  }, [shouldRenderBanner])

  const banner = useMemo(() => {
    return (
      typeof bannerHtml === 'string' && (
        <div
          style={{
            display: showPlaceholder ? 'none' : 'block',
          }}
          // The banner is HTML we wrote, it's not user-generated.
          // eslint-disable-next-line react/no-danger
          dangerouslySetInnerHTML={{__html: bannerHtml}}
        />
      )
    )
  }, [bannerHtml, showPlaceholder])

  if (!shouldLoadBanner) {
    return null
  }

  return (
    <>
      {banner}
      <CopilotSummarizeBannerPlaceholder hide={!showPlaceholder} />
    </>
  )
}
