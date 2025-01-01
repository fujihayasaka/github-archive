// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {screen} from '@testing-library/react'
import {IS_SERVER as MOCK_IS_SERVER, IS_BROWSER as MOCK_IS_BROWSER} from '../ssr'

const mockIsServer = jest.fn()
const mockIsBrowser = jest.fn()
jest.mock('../ssr', () => ({
  get IS_SERVER() {
    return mockIsServer()
  },

  get IS_BROWSER() {
    return mockIsBrowser()
  },
}))

const {wasServerRendered, IS_SERVER, IS_BROWSER} = jest.requireActual('../ssr')

describe('SSR in browser', () => {
  afterEach(jest.resetAllMocks)

  describe('IS_SERVER', () => {
    it('should return false in browser environment', () => {
      expect(globalThis.document).toBeDefined()
      expect(IS_SERVER).toBe(false)
    })

    it('can be mocked', () => {
      mockIsServer.mockReturnValue(true)
      expect(MOCK_IS_SERVER).toBe(true)
      expect(IS_SERVER).toBe(false)
      expect(IS_BROWSER).toBe(true)
    })
  })

  describe('IS_BROWSER', () => {
    it('should return true in browser environment', () => {
      expect(globalThis.document).toBeDefined()
      expect(IS_BROWSER).toBe(true)
    })

    it('can be mocked', () => {
      mockIsBrowser.mockReturnValue(false)
      expect(MOCK_IS_BROWSER).toBe(false)
      expect(IS_SERVER).toBe(false)
      expect(IS_BROWSER).toBe(true)
    })
  })

  describe('wasServerRendered', () => {
    afterEach(() => {
      screen.queryByTestId('react-app')?.remove()
      screen.queryByTestId('react-partial')?.remove()
    })

    it('returns true if react app was rendered with ssr', () => {
      renderReactAppNode({dataSSR: 'true'})
      expect(wasServerRendered()).toBe(true)
    })

    it('returns false if react app was rendered without ssr', () => {
      renderReactAppNode({dataSSR: 'false'})
      expect(wasServerRendered()).toBe(false)
    })

    it('ignores ssr for react partials in general', () => {
      renderReactPartialNode({dataSSR: 'true', partialName: 'some-normal-partial'})
      expect(wasServerRendered()).toBe(false)
    })

    it('return false for repos overview react partial when rendered without ssr', () => {
      renderReactPartialNode({dataSSR: 'false', partialName: 'repos-overview'})
      expect(wasServerRendered()).toBe(false)
    })

    it('return true for repos overview react partial when rendered with ssr', () => {
      renderReactPartialNode({dataSSR: 'true', partialName: 'repos-overview'})
      expect(wasServerRendered()).toBe(true)
    })
  })
})

function renderReactAppNode({dataSSR}: {dataSSR: 'true' | 'false'}) {
  const reactApp = document.createElement('react-app')
  reactApp.setAttribute('data-ssr', dataSSR)
  reactApp.setAttribute('data-testid', 'react-app')
  document.body.appendChild(reactApp)
}

function renderReactPartialNode({dataSSR, partialName}: {dataSSR: 'true' | 'false'; partialName: string}) {
  const reactPartial = document.createElement('react-partial')
  reactPartial.setAttribute('data-ssr', dataSSR)
  reactPartial.setAttribute('data-testid', 'react-partial')
  reactPartial.setAttribute('partial-name', partialName)
  document.body.appendChild(reactPartial)
}
