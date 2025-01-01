import {getBaseFetchHeaders} from '@github-ui/fetch-headers'

// eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
const originalFetch = window.fetch

const overrideFetch = (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
  if (input instanceof Request) {
    const newHeaders = {
      ...Object.fromEntries(input.headers.entries()),
      ...getBaseFetchHeaders(),
    }

    const newInput = new Request(input, {
      headers: newHeaders,
    })

    return originalFetch(newInput)
  } else {
    const headers: HeadersInit = {
      ...(init?.headers ?? {}),
      ...getBaseFetchHeaders(),
    }

    return originalFetch(new Request(input, {...init, headers}))
  }
}

if (
  process.env.NODE_ENV === 'test' ||
  // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
  (document.documentElement.hasAttribute('override-fetch') && window.fetch !== overrideFetch)
) {
  window.fetch = overrideFetch
}
