import {assert, setup, suite, test} from '@github-ui/browser-tests'
import '../fetch-overrides'

const originalRequest = window.Request

suite('Fetch overrides tests', () => {
  let requestCalls: unknown[][] = []
  let requestObjects: Request[] = []

  // Record all calls made by the fetch override and their corresponding request objects
  class CustomRequest extends originalRequest {
    constructor(input: RequestInfo | URL, init?: RequestInit | undefined) {
      super(input, init)
      requestCalls.push([input, init])
      requestObjects.push(this)
    }
  }

  setup(async () => {
    window.Request = CustomRequest as unknown as typeof originalRequest
  })

  teardown(() => {
    requestCalls = []
    requestObjects = []
    window.Request = originalRequest
  })

  test('adds header to any XHR request', async () => {
    fetch('/test')

    assert.deepEqual(requestCalls?.[0]?.[1], {
      headers: {
        'X-Requested-With': 'XMLHttpRequest',
      },
    })
  })

  test('passes any additional headers to request', async () => {
    fetch(new Request('/test', {headers: {'Some-Header': 'true'}}))

    assert.deepEqual(Object.fromEntries(requestObjects?.[1]?.headers.entries() || []), {
      'some-header': 'true',
      'x-requested-with': 'XMLHttpRequest',
    })
  })

  test('using both input and init', async () => {
    fetch('/test', {headers: {'Some-Header': 'true'}})

    assert.deepEqual(requestCalls?.[0]?.[1], {
      headers: {
        'Some-Header': 'true',
        'X-Requested-With': 'XMLHttpRequest',
      },
    })
  })
})
