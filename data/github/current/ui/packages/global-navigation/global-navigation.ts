import type {ContextRegionElement} from '@github-ui/context-region-element'
import type {ContextRegionControllerElement} from '@github-ui/context-region-element/context-region-controller-element'
import type {CrumbOptions} from './types'

// store a reference to the callback function that will be executed once the context region is connected
let pendingOperation = null as ((contextRegion: ContextRegionElement) => void) | null
let waitingForContextRegion = false

// The context-region element might not be available immediately on page load.
// This function sets up a one-time event listener that executes the pending operation
// when the context region connects to the DOM, removing the need for existence checks.
function waitForContextRegion(): void {
  // only set up the event listener once
  if (waitingForContextRegion) return

  waitingForContextRegion = true
  const contextRegionController = document.querySelector<ContextRegionControllerElement>('context-region-controller')

  if (!contextRegionController) {
    // If the context region's controller is not found, we can't set up the event listener
    return
  }

  contextRegionController.addEventListener(
    'context-region-connected',
    () => {
      if (pendingOperation) {
        pendingOperation(contextRegionController.contextRegion)
        pendingOperation = null
      }
    },
    {once: true},
  )
}

export function getContextRegion(): ContextRegionElement | null {
  const contextRegion = document.querySelector<ContextRegionElement>('context-region')

  if (!contextRegion) {
    if (process.env.NODE_ENV === 'development') {
      // eslint-disable-next-line no-console
      console.error(
        `The global navigation's context region cannot be found! Make sure the <context-region> element exists on the page before calling any of the global navigation breadcrumb methods.`,
      )
    }

    return null
  }

  // Make sure the context region is fully connected to the DOM
  if (!contextRegion.isConnected) {
    return null
  }

  // Additional check to ensure custom methods are available (if one of the methods is missing, they likely all are)
  if (!contextRegion.pushCrumb || typeof contextRegion.pushCrumb !== 'function') {
    return null
  }

  return contextRegion
}

// Executes the callback immediately if context-region is ready, or queues it for when the element becomes available
export function withContextRegion(operation: (region: ContextRegionElement) => void): void {
  const contextRegion = getContextRegion()

  if (contextRegion) {
    operation(contextRegion)
    return
  }

  // if the context region is not ready, queue the operation and listen for readiness
  pendingOperation = operation
  waitForContextRegion()
}

export function pushNavigationBreadcrumb(crumb: CrumbOptions) {
  withContextRegion(contextRegion => contextRegion.pushCrumb(crumb))
}

export function popNavigationBreadcrumb() {
  withContextRegion(contextRegion => contextRegion.popCrumb())
}

export function replaceNavigationBreadcrumbs(crumbs: CrumbOptions[]) {
  withContextRegion(contextRegion => contextRegion.replaceCrumbs(crumbs))
}

export function renameCurrentNavigationBreadcrumb(label: string) {
  withContextRegion(contextRegion => contextRegion.renameCurrentCrumb(label))
}

export function replaceCurrentNavigationBreadcrumb(crumb: CrumbOptions) {
  withContextRegion(contextRegion => contextRegion.replaceCurrentCrumb(crumb))
}
