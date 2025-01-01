import type {Position} from '@github/turbo/dist/types/core/types'
import {noop} from '@github-ui/noop'
import {ssrSafeLocation, ssrSafeWindow} from '@github-ui/ssr-utils'
import {useLayoutEffect} from '@github-ui/use-layout-effect'

const scrollMap = new Map<string, Position>()

let installed = false
let previousHref = ssrSafeLocation.href

async function saveScrollPosition() {
  const {session} = await import('@github/turbo')

  document.addEventListener('turbo:click', event => {
    previousHref = event.detail.url
  })

  window.addEventListener('popstate', () => {
    const {scrollPosition} =
      session.history.getRestorationDataForIdentifier(session.history.restorationIdentifier) || {}
    if (!scrollPosition) return
    scrollMap.set(window.location.href, scrollPosition)
  })
}

export async function installScrollRestoration() {
  if (ssrSafeWindow) {
    if (installed) return
    await saveScrollPosition()
    installed = true
  }
}

function useScrollRestorationInBrowser() {
  useLayoutEffect(() => {
    const href = window.location.href

    // When clicking on the same hash link, don't restore scroll
    if (href === previousHref && href.includes('#')) return
    previousHref = href

    const scroll = scrollMap.get(href)

    if (!scroll) return
    const timeout = setTimeout(() => {
      window.scrollTo(scroll.x, scroll.y)
    }, 0)
    return () => {
      clearTimeout(timeout)
    }
  })
}

export function clear() {
  scrollMap.clear()
  installed = false
}
/**
 * This hook restores turbo-scroll-restoration position AFTER the page has been rendered.
 * Otherwise, turbo was restoring scroll on the page before react had rendered.
 */
export const useScrollRestoration = ssrSafeWindow ? useScrollRestorationInBrowser : noop
