import {sendStats} from '@github-ui/stats'
import {sendToHydro} from './hydro-stats'
import {wasServerRendered} from '@github-ui/ssr-utils'

export const observeLongAnimationFrames = () => {
  if (
    typeof PerformanceObserver !== 'undefined' &&
    (PerformanceObserver.supportedEntryTypes || []).includes('long-animation-frame')
  ) {
    const observer = new PerformanceObserver(function (list) {
      const longAnimationFrameEntries = list.getEntries()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const longAnimationFrames = longAnimationFrameEntries.map(({name, duration, blockingDuration}: any) => ({
        name,
        duration,
        blockingDuration,
        url: window.location.href,
      }))

      if (longAnimationFrames.length > 0) {
        sendToHydro({longAnimationFrames: longAnimationFrameEntries, ssr: wasServerRendered()})
      }

      sendStats({longAnimationFrames})
    })
    observer.observe({type: 'long-animation-frame', buffered: true})
  }
}
