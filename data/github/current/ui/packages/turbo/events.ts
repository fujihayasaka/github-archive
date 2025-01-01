// eslint-disable-next-line no-restricted-imports
import {observe} from '@github/selector-observer'
import {isTurboFrame, waitForStylesheets, dispatchTurboReload, replaceElementAttributes, copyScriptTag} from './utils'
import {beginProgressBar, completeProgressBar} from './progress-bar'
import isHashNavigation from '@github-ui/is-hash-navigation'
import {getCachedAttributes, setDocumentAttributesCache} from './cache'
import {ssrSafeWindow, ssrSafeDocument} from '@github-ui/ssr-utils'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {inSoftNav} from '@github-ui/soft-nav/utils'
import {startSoftNav} from '@github-ui/soft-nav/state'
import type {FetchRequest} from '@github/turbo/dist/types/http/fetch_request'
import type {FrameElement} from '@github/turbo'
import {addValidNonce} from '@github-ui/fetch-nonce'
import {CLIENT_VERSION_HTTP_HEADER, getClientVersion} from '@github-ui/client-version'
import {updateHtmlHighContrastMode} from '@github-ui/high-contrast-cookie'

let responseFailed = false
let errorDocument: Document | null = null

if (ssrSafeWindow) {
  // We want to make sure that links inside a `data-turbo-frame` container also have the data attribute.
  observe('[data-turbo-frame]', {
    constructor: HTMLElement,
    add(el) {
      if (el.tagName === 'A' || el.getAttribute('data-turbo-frame') === '') return

      for (const link of el.querySelectorAll('a:not([data-turbo-frame])')) {
        link.setAttribute('data-turbo-frame', el.getAttribute('data-turbo-frame') || '')
      }
    },
  })
}

ssrSafeDocument?.addEventListener('turbo:click', function (event) {
  if (!(event.target instanceof HTMLElement)) return

  // If we are already in a soft nav, it means the navigation is handled by a frame.
  if (isFeatureEnabled('disable_turbo_visit') && !inSoftNav()) {
    event.preventDefault()
    return
  }

  // https://github.com/hotwired/turbo/issues/539
  // If we are doing a hash navigation, we want to prevent Turbo from performing a visit
  // so it won't mess with focus styles.
  if (isHashNavigation(location.href, event.detail.url)) {
    event.preventDefault()
    // return early so we don't start a soft-nav
    return
  }

  // Here is where ALL non-frame Turbo navigation starts. We start by emitting the `soft-nav:start` event with the correct `turbo` mechanism.
  if (!event.defaultPrevented) {
    startSoftNav('turbo')
  }
})

// Emulate `onbeforeunload` event handler for Turbo navigations to
// support warning a user about losing unsaved content
ssrSafeDocument?.addEventListener('turbo:before-fetch-request', function (event) {
  try {
    const unloadMessage = window.onbeforeunload?.(event)

    if (unloadMessage) {
      const navigate = confirm(unloadMessage)
      if (navigate) {
        window.onbeforeunload = null
      } else {
        event.preventDefault()
        completeProgressBar()
      }
    }
  } catch (e) {
    if (!(e instanceof Error)) throw e
    if (e.message !== 'Permission denied to access object') throw e
  }
})

ssrSafeDocument?.addEventListener('turbo:before-fetch-request', event => {
  if (event.defaultPrevented) return

  const frame = event.target as Element
  if (isTurboFrame(frame)) {
    beginProgressBar()
  }

  const ev = event as CustomEvent

  if (isFeatureEnabled('client_version_header')) {
    ev.detail.fetchOptions.headers[CLIENT_VERSION_HTTP_HEADER] = getClientVersion()
  }

  // attach a Turbo specific header for visit requests so the server can track Turbo usage
  if (!ev.detail.fetchOptions.headers['Turbo-Frame']) {
    ev.detail.fetchOptions.headers['Turbo-Visit'] = 'true'
  }
})

/**
 * I think this was upstreamed entirely - we can probably delete this emitter and just listen to fetch-request-error?
 */
// TODO: turbo upstream will emit this event eventually https://github.com/hotwired/turbo/pull/640
// and we can remove the types above
const frame = ssrSafeDocument?.createElement('turbo-frame') as unknown as FrameElement
const controllerPrototype = Object.getPrototypeOf(frame.delegate)
const originalRequestErrored = controllerPrototype.requestErrored
controllerPrototype.requestErrored = function (request: FetchRequest, error: Error) {
  this.element.dispatchEvent(
    new CustomEvent('turbo:fetch-error', {
      bubbles: true,
      detail: {request, error},
    }),
  )
  return originalRequestErrored.apply(this, request, error)
}

declare global {
  interface DocumentEventMap {
    'turbo:fetch-error': CustomEvent<{request: FetchRequest; error: Error}>
  }
}

// when a frame fetch request errors due to a network error
// we reload the page to prevent hanging the progress bar indefinitely
ssrSafeDocument?.addEventListener('turbo:fetch-error', event => {
  // we don't want to reload the page due to an error on a form
  // since we might throw away the users work or submit the form again
  // other handling would be needed for this use case
  if (event.target instanceof HTMLFormElement) {
    return
  }

  const fetchRequest = event.detail.request

  window.location.href = fetchRequest.location.href
  event.preventDefault()
})

ssrSafeDocument?.addEventListener('turbo:before-fetch-response', async event => {
  const fetchResponse = event.detail.fetchResponse

  responseFailed = fetchResponse.statusCode >= 500
  // Turbo is misbehaving when we Drive to our 404 page, so we
  // can force a reload if the response is 404 and prevent Turbo
  // from continuing.
  if (fetchResponse.statusCode === 404) {
    dispatchTurboReload(fetchResponse.statusCode.toString())
    window.location.href = fetchResponse.location.href
    event.preventDefault()
  }

  const newNonce = fetchResponse.header('X-Fetch-Nonce')
  if (newNonce) addValidNonce(newNonce)

  if (responseFailed || !newNonce) {
    const responseHTML = await fetchResponse.responseHTML
    const parsedHTML = new DOMParser().parseFromString(responseHTML ?? '', 'text/html')

    if (responseFailed) {
      errorDocument = parsedHTML
      return
    }
    if (!newNonce) handleFetchNonceFromDocument(parsedHTML)
  }
})

ssrSafeDocument?.addEventListener('turbo:frame-render', event => {
  if (isTurboFrame(event.target)) {
    completeProgressBar()
  }
})

// copy over new attributes on <html> to the existing page
ssrSafeDocument?.addEventListener('turbo:before-render', async event => {
  event.preventDefault()

  event.detail.render = customDriveRender

  await waitForStylesheets()

  event.detail.resume(true)

  // Update <html> attributes
  replaceElementAttributes(document.documentElement, event.detail.newBody.ownerDocument.documentElement)
  // Update <html> high contrast mode
  updateHtmlHighContrastMode()
  setDocumentAttributesCache()
})

// Fallback in case the Turbo response did not add X-Fetch-Nonce header. This may happen if the browser
// fails to add the Turbo header to the request for some reason.
function handleFetchNonceFromDocument(html: Document) {
  const nonce = html.querySelector<HTMLMetaElement>('#pjax-head meta[name=fetch-nonce], head meta[name=fetch-nonce]')
    ?.content

  if (nonce) addValidNonce(nonce)
}

const nextEventLoopTick = () =>
  new Promise<void>(resolve => {
    setTimeout(() => resolve(), 0)
  })

const customDriveRender = async (currentBody: HTMLBodyElement, newBody: HTMLBodyElement) => {
  await nextEventLoopTick()

  if (responseFailed && errorDocument) {
    document.documentElement.replaceWith(errorDocument.documentElement)
    for (const script of document.querySelectorAll('script')) {
      const newScript = copyScriptTag(script)
      if (newScript) script.replaceWith(newScript)
    }
    return
  }

  const currentTurboBody = currentBody.querySelector('[data-turbo-body]')
  const newTurboBody = newBody.querySelector('[data-turbo-body]')

  if (currentTurboBody && newTurboBody) {
    replaceElementAttributes(currentBody, newBody)
    currentTurboBody.replaceWith(newTurboBody)
  } else {
    dispatchTurboReload('missing_turbo_body')
    window.location.reload()
  }
}

ssrSafeWindow?.addEventListener('popstate', () => {
  const currentDocument = document.documentElement
  const cachedAttributes = getCachedAttributes()

  if (!cachedAttributes) return

  for (const attr of currentDocument.attributes) {
    if (!cachedAttributes.find(cached => cached.nodeName === attr.nodeName)) {
      currentDocument.removeAttribute(attr.nodeName)
    }
  }

  for (const attr of cachedAttributes) {
    if (currentDocument.getAttribute(attr.nodeName) !== attr.nodeValue) {
      currentDocument.setAttribute(attr.nodeName, attr.nodeValue!)
    }
  }
})
