import {addBaseFetchHeaders} from '@github-ui/fetch-headers'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import '@github/include-fragment-element'

if (ssrSafeWindow) {
  ssrSafeWindow.IncludeFragmentElement.prototype.fetch = function (request: Request) {
    const nonce = this.getAttribute('data-nonce') || ''

    addBaseFetchHeaders(request.headers, nonce)
    return window.fetch(request)
  }
}
