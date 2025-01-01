import {isFeatureEnabled} from '@github-ui/feature-flags'
import {sendEvent as hydroSendEvent, currentCatalogService, type SendEventContext} from '@github-ui/hydro-analytics'
import {postTask} from '@github-ui/scheduler'

// eslint-disable-next-line no-barrel-files/no-barrel-files
export type {SendEventContext} from '@github-ui/hydro-analytics'

declare const process: {
  env: {
    NODE_ENV: string
  }
}

let catalogService: string | undefined

export function sendEvent(type: string, context: SendEventContext = {}) {
  // Terser doesn't recognize `performance` as side-effect free—mark
  // it so it can be tree-shaken when not in development mode.
  // See: https://terser.org/docs/miscellaneous/#annotations
  const start = /*#__PURE__ */ performance.now()

  const isScheduling = isFeatureEnabled('github_models_scheduled_hydro_events')

  if (!isScheduling) {
    hydroSendEvent(type, context)
  } else {
    // Set the catalog service early, as by the time the scheduler runs, the
    // meta tag containing the catalog-service may have changed, leading to
    // incorrect attribution.
    // TODO: This is arguably a leaky abstraction; a proper fix likely belongs
    // in hydro-analytics itself; but for now, to keep scope minimal, we handle
    // it here.
    context['service'] = catalogService ||= currentCatalogService()

    postTask(
      function () {
        hydroSendEvent(type, context)
      },
      {
        priority: 'background',
      },
    )
  }

  if (process.env.NODE_ENV === 'development') {
    performance.measure(`hydro: ${isScheduling ? 'schedule' : 'sync'} sendEvent`, {
      detail: {type, context},
      start,
      end: performance.now(),
    })
  }
}
