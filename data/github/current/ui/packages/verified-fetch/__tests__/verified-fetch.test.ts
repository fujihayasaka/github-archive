import {reactFetch, reactFetchJSON, verifiedFetch, verifiedFetchJSON} from '../verified-fetch'

let originalFetch: typeof fetch

// @ts-expect-error overriding window.location in tests
delete window.location
window.location = {} as string & Location
Object.defineProperty(window, 'location', {
  writable: true,
  value: {
    origin: 'https://github.com',
    href: 'https://github.com/',
  },
})

beforeEach(() => {
  window.location.href = 'https://github.com/'

  originalFetch = globalThis.fetch
  globalThis.fetch = jest.fn()
})

afterEach(() => {
  globalThis.fetch = originalFetch
})

describe('verifiedFetch', () => {
  test('calls fetch with verification headers', () => {
    verifiedFetch('/', {method: 'POST', headers: {'Content-Type': 'text/html'}})

    expect(globalThis.fetch).toHaveBeenCalledWith('/', {
      method: 'POST',
      headers: {
        'Content-Type': 'text/html',
        'GitHub-Verified-Fetch': 'true',
        'X-Requested-With': 'XMLHttpRequest',
        'X-Fetch-Nonce': expect.any(String),
      },
    })
  })

  test('calls fetch with verification header and an absolute path', () => {
    verifiedFetch('https://github.com/', {method: 'POST', headers: {'Content-Type': 'text/html'}})

    expect(globalThis.fetch).toHaveBeenCalledWith('https://github.com/', {
      method: 'POST',
      headers: {
        'Content-Type': 'text/html',
        'GitHub-Verified-Fetch': 'true',
        'X-Requested-With': 'XMLHttpRequest',
        'X-Fetch-Nonce': expect.any(String),
      },
    })
  })

  test('rejects an attempt to make a cross-origin request via an absolute URL', () => {
    expect(() => {
      verifiedFetch('https://evilcorp.com', {method: 'POST', headers: {'Content-Type': 'text/html'}})
    }).toThrow('Can not make cross-origin requests from verifiedFetch')
  })

  test('rejects an attempt to make a cross-origin request via a protocol-relative URL', () => {
    expect(() => {
      verifiedFetch('//evilcorp.com', {method: 'POST', headers: {'Content-Type': 'text/html'}})
    }).toThrow('Can not make cross-origin requests from verifiedFetch')
  })

  describe('url resolution', () => {
    test('fetches full url', () => {
      window.location.href = 'https://github.com/foo/bar'
      verifiedFetch('https://github.com/baz', {method: 'POST', headers: {'Content-Type': 'text/html'}})

      expect(globalThis.fetch).toHaveBeenCalledWith('https://github.com/baz', {
        method: 'POST',
        headers: {
          'Content-Type': 'text/html',
          'GitHub-Verified-Fetch': 'true',
          'X-Requested-With': 'XMLHttpRequest',
          'X-Fetch-Nonce': expect.any(String),
        },
      })
    })

    test('fetches empty url', () => {
      window.location.href = 'https://github.com/foo/bar'
      verifiedFetch('', {method: 'POST', headers: {'Content-Type': 'text/html'}})

      expect(globalThis.fetch).toHaveBeenCalledWith('/foo/bar', {
        method: 'POST',
        headers: {
          'Content-Type': 'text/html',
          'GitHub-Verified-Fetch': 'true',
          'X-Requested-With': 'XMLHttpRequest',
          'X-Fetch-Nonce': expect.any(String),
        },
      })
    })

    test('fetches url relative to origin', () => {
      window.location.href = 'https://github.com/foo/bar'
      verifiedFetch('/baz', {method: 'POST', headers: {'Content-Type': 'text/html'}})

      expect(globalThis.fetch).toHaveBeenCalledWith('/baz', {
        method: 'POST',
        headers: {
          'Content-Type': 'text/html',
          'GitHub-Verified-Fetch': 'true',
          'X-Requested-With': 'XMLHttpRequest',
          'X-Fetch-Nonce': expect.any(String),
        },
      })
    })

    test('fetches url relative to current path', () => {
      window.location.href = 'https://github.com/foo/bar'
      document.location.href = 'https://github.com/foo/bar'
      verifiedFetch('baz', {method: 'POST', headers: {'Content-Type': 'text/html'}})

      expect(globalThis.fetch).toHaveBeenCalledWith('/foo/baz', {
        method: 'POST',
        headers: {
          'Content-Type': 'text/html',
          'GitHub-Verified-Fetch': 'true',
          'X-Requested-With': 'XMLHttpRequest',
          'X-Fetch-Nonce': expect.any(String),
        },
      })
    })
  })

  describe('tracing params', () => {
    test('adds tracing and features params from window to fetch url', () => {
      window.location.href = 'https://github.com/?_tracing=true&_features=a,b,c'

      verifiedFetch('https://github.com/foo', {method: 'POST', headers: {'Content-Type': 'text/html'}})

      expect(globalThis.fetch).toHaveBeenCalledWith('https://github.com/foo?_features=a%2Cb%2Cc&_tracing=true', {
        method: 'POST',
        headers: {
          'Content-Type': 'text/html',
          'GitHub-Verified-Fetch': 'true',
          'X-Requested-With': 'XMLHttpRequest',
          'X-Fetch-Nonce': expect.any(String),
        },
      })
    })

    test('does not override params if they are in the url already', () => {
      window.location.href = 'https://github.com/?_tracing=true&_features=a,b,c'

      verifiedFetch('https://github.com/foo?_tracing=false&_features=d,e,f', {
        method: 'POST',
        headers: {'Content-Type': 'text/html'},
      })

      expect(globalThis.fetch).toHaveBeenCalledWith('https://github.com/foo?_tracing=false&_features=d,e,f', {
        method: 'POST',
        headers: {
          'Content-Type': 'text/html',
          'GitHub-Verified-Fetch': 'true',
          'X-Requested-With': 'XMLHttpRequest',
          'X-Fetch-Nonce': expect.any(String),
        },
      })
    })
  })
})

describe('verifiedFetchJSON', () => {
  test('stringifies bodies and appends JSON headers', () => {
    verifiedFetchJSON('/', {method: 'POST', body: {foo: 'bar'}})

    expect(globalThis.fetch).toHaveBeenCalledWith('/', {
      method: 'POST',
      body: JSON.stringify({foo: 'bar'}),
      headers: {
        'GitHub-Verified-Fetch': 'true',
        'X-Requested-With': 'XMLHttpRequest',
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-Fetch-Nonce': expect.any(String),
      },
    })
  })
})

describe('reactFetch', () => {
  test('marks as React request and makes a verifiedFetch request', () => {
    reactFetch('/', {method: 'POST', headers: {'Content-Type': 'text/html'}})

    expect(globalThis.fetch).toHaveBeenCalledWith('/', {
      method: 'POST',
      headers: {
        'Content-Type': 'text/html',
        'GitHub-Verified-Fetch': 'true',
        'X-Requested-With': 'XMLHttpRequest',
        'GitHub-Is-React': 'true',
        'X-Fetch-Nonce': expect.any(String),
      },
    })
  })
})

describe('reactFetchJSON', () => {
  test('marks as React request and makes a verifiedFetchJSON request', () => {
    reactFetchJSON('/', {method: 'POST', body: {foo: 'bar'}})

    expect(globalThis.fetch).toHaveBeenCalledWith('/', {
      method: 'POST',
      body: JSON.stringify({foo: 'bar'}),
      headers: {
        'GitHub-Verified-Fetch': 'true',
        'X-Requested-With': 'XMLHttpRequest',
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'GitHub-Is-React': 'true',
        'X-Fetch-Nonce': expect.any(String),
      },
    })
  })
})
