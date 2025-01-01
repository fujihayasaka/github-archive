// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import {render} from '@github-ui/react-core/test-utils'
import type React from 'react'
import {useSearchParams} from '../use-navigate'
import {visit} from '@github/turbo'
import {screen} from '@testing-library/react'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {RoutesContext} from '@github-ui/react-core/routes-context'

const navigateFn = vi.fn()

vi.mock('react-router-dom', async () => {
  const originalModule = await vi.importActual('react-router-dom')

  return {
    ...originalModule,
    useNavigate: () => navigateFn,
  }
})

vi.mock('@github-ui/soft-nav/state', () => ({startSoftNav: vi.fn()}))
vi.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: () => false,
  getEnabledFeatures: () => [],
}))
vi.mock('@github/turbo', () => ({visit: vi.fn()}))

const TestButton = ({params}: {params: URLSearchParams}) => {
  const [, setSearchParams] = useSearchParams()
  return <button onClick={() => setSearchParams(params)}>Navigate</button>
}

beforeEach(() => {
  vi.clearAllMocks()
})

describe('useSearchParams', () => {
  it('navigates using React router for destinations within the app', async () => {
    const Wrapper: React.FC<{children: React.ReactNode}> = ({children}) => {
      return (
        <RoutesContext.Provider
          value={{
            routes: [jsonRoute({path: '/', Component: () => null})],
          }}
        >
          {children}
        </RoutesContext.Provider>
      )
    }

    const {user} = render(<TestButton params={new URLSearchParams({a: 'a'})} />, {wrapper: Wrapper})
    await user.click(screen.getByText('Navigate'))
    expect(navigateFn).toHaveBeenCalledWith({pathname: '/', search: 'a=a'}, {})
    expect(visit).not.toHaveBeenCalled()
  })
})
