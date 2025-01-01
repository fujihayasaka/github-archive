import {sendStats} from '@github-ui/stats'
import {sendToHydro} from './hydro-stats'
import {wasServerRendered} from '@github-ui/ssr-utils'

export const observeLongTasks = () => {
  if (
    typeof PerformanceObserver !== 'undefined' &&
    (PerformanceObserver.supportedEntryTypes || []).includes('longtask')
  ) {
    const observer = new PerformanceObserver(function (list) {
      const longTasksEntries = list.getEntries()
      const longTasks = longTasksEntries.map(({name, duration}) => ({name, duration, url: window.location.href}))
      sendStats({longTasks})

      if (longTasks.length > 0) sendToHydro({longTasks: longTasksEntries, ssr: wasServerRendered()})
    })
    observer.observe({type: 'longtask', buffered: true})
  }
}
