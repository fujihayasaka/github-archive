import {ScrollRestoration} from 'react-router-dom'
import {installScrollRestoration, useScrollRestoration} from '../use-scroll-restoration'

installScrollRestoration()

export function CombinedScrollRestoration() {
  // This hook restores turbo-scroll-restoration only on initial render because of the useLayoutEffect.
  // This only happens when you navigate from a turbo link to a react link.
  useScrollRestoration()

  // In some tests the scroll restoration causes an unexpected delay in jsdom that leads to flakes, so we don't render it there.
  if (typeof jest !== 'undefined') return null

  // Otherwise, we let react-router handle scroll restoration on soft navigation.
  return <ScrollRestoration />
}
