import {failSoftNav, renderedSoftNav, succeedSoftNav} from '@github-ui/soft-nav/state'
import {inSoftNav} from '@github-ui/soft-nav/utils'
import {ssrSafeDocument, ssrSafeLocation} from '@github-ui/ssr-utils'
import {sendStats} from '@github-ui/stats'
import {useEffect, useRef} from 'react'
import type {Location} from 'react-router-dom'

import type {PageError} from './app-routing-types'

function updateVisitorPayload(pathname: string) {
  const visitorMeta = ssrSafeDocument?.querySelector<HTMLMetaElement>('meta[name=visitor-payload]')

  if (!visitorMeta) return

  const payload = JSON.parse(atob(visitorMeta.content))
  payload.referrer = new URL(pathname, ssrSafeLocation.origin).href

  visitorMeta.content = btoa(JSON.stringify(payload))
}

export const useSoftNavLifecycle = (location: Location, isLoading: boolean, error: PageError | null) => {
  const lastRecordedKey = useRef<string | undefined>(undefined)
  useEffect(() => {
    if (!isLoading && (lastRecordedKey.current === undefined || lastRecordedKey.current !== location.key)) {
      // At this point, React is done rendering, so we can end the navigation
      if (inSoftNav()) {
        finishSoftNav(error)
        updateVisitorPayload(location.pathname)
      } else {
        finishHardNav(error)
      }

      lastRecordedKey.current = location.key
    }
  }, [location.key, location.pathname, isLoading, error])
}

const finishSoftNav = (error: PageError | null) => {
  if (error) {
    failSoftNav()
  } else {
    renderedSoftNav()
    succeedSoftNav()
  }
}

const finishHardNav = (error: PageError | null) => {
  // We don't want to measure pages with errors.
  if (error) return

  const navDuration = getReactNavDuration()

  if (!navDuration) return

  sendStats({
    requestUrl: window.location.href,
    distributionKey: 'REACT_NAV_DURATION',
    distributionValue: Math.round(navDuration),
    distributionTags: ['REACT_NAV_HARD'],
  })
}

const reactNavDurationStat = 'react_nav_duration'
function getReactNavDuration() {
  window.performance.measure(reactNavDurationStat)
  const measures = window.performance.getEntriesByName(reactNavDurationStat)
  const measure = measures.pop()
  return measure ? measure.duration : null
}
