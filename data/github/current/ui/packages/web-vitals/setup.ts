import {onCLS, onFCP, onFID, onLCP, onTTFB} from 'web-vitals/attribution'
import {sendSoftVitals, sendTimingResults, sendVitals} from './timing-stats'
import {ssrSafeDocument} from '@github-ui/ssr-utils'
import {SOFT_NAV_STATE} from '@github-ui/soft-nav/states'
import {HPCObserver} from './hpc'
import {INPObserver} from './inp/observer'

export function setupWebVitals() {
  sendTimingResults()
  onCLS(sendVitals)
  onFCP(sendVitals)
  onFID(sendVitals)
  onLCP(sendVitals)
  onTTFB(sendVitals)

  onLCP(sendSoftVitals, {reportSoftNavs: true})
  onCLS(sendSoftVitals, {reportSoftNavs: true})

  const inpObserver = new INPObserver(sendVitals)
  inpObserver.observe()

  // Start HPC at page load.
  let hpcObserver = new HPCObserver({soft: false, mechanism: 'hard', latestHPCElement: null})
  hpcObserver.connect()
  // Any time we trigger a new soft navigation, we want to reset HPC.
  ssrSafeDocument?.addEventListener(SOFT_NAV_STATE.START, ({mechanism}) => {
    hpcObserver.disconnect()
    hpcObserver = new HPCObserver({soft: true, mechanism, latestHPCElement: document.querySelector('[data-hpc]')})
    hpcObserver.connect()
  })
}
