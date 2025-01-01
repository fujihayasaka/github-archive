import {onCLS, onFCP, onFID, onLCP, onTTFB} from 'web-vitals/attribution'
import {sendSoftVitals, sendTimingResults, sendVitals} from './timing-stats'
import {ssrSafeDocument} from '@github-ui/ssr-utils'
import {SOFT_NAV_STATE} from '@github-ui/soft-nav/states'
import {HPCObserver} from './hpc'
import {INPObserver} from './inp/observer'
import {ElementTimingObserver} from './element-timing/observer'
import {observeLongTasks} from './long-tasks'
import {observeLongAnimationFrames} from './long-animation-frames'

export function setupWebVitals() {
  sendTimingResults()
  onCLS(sendVitals)
  onFCP(sendVitals)
  onFID(sendVitals)
  onLCP(sendVitals)
  onTTFB(sendVitals)
  observeLongTasks()
  observeLongAnimationFrames()

  onLCP(sendSoftVitals, {reportSoftNavs: true})
  onCLS(sendSoftVitals, {reportSoftNavs: true})

  const inpObserver = new INPObserver(sendVitals)
  inpObserver.observe()

  const etObserver = new ElementTimingObserver(sendVitals)
  etObserver.observe()

  // Start HPC at page load.
  let hpcObserver = new HPCObserver({soft: false, mechanism: 'hard', latestHPCElement: null})
  hpcObserver.connect()
  // Any time we trigger a new soft navigation, we want to reset HPC.
  ssrSafeDocument?.addEventListener(SOFT_NAV_STATE.START, ({mechanism}) => {
    hpcObserver.disconnect()
    hpcObserver = new HPCObserver({soft: true, mechanism, latestHPCElement: document.querySelector('[data-hpc]')})
    hpcObserver.connect()
  })

  ssrSafeDocument?.addEventListener(SOFT_NAV_STATE.REPLACE_MECHANISM, ({mechanism}) => {
    hpcObserver.mechanism = mechanism
  })
}
