// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import {render} from '@github-ui/react-core/test-utils'
import type React from 'react'
import {useNavigate as useNavigateToTest} from '../use-navigate'
import {visit} from '@github/turbo'
import {screen, waitFor} from '@testing-library/react'
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

const Wrapper: React.FC<{children: React.ReactNode}> = ({children}) => {
  return (
    <RoutesContext.Provider
      value={{
        routes: [jsonRoute({path: '/a', Component: () => null})],
      }}
    >
      {children}
    </RoutesContext.Provider>
  )
}

const TestButton = ({path}: {path: string}) => {
  const navigate = useNavigateToTest()
  return <button onClick={() => navigate(path)}>Navigate</button>
}

const TestButtonWithReload = ({path}: {path: string}) => {
  const navigate = useNavigateToTest()
  return <button onClick={() => navigate(path, {reloadDocument: true})}>Navigate</button>
}

beforeEach(() => {
  vi.clearAllMocks()
})

describe('useNavigate', () => {
  it('navigates using React router for destinations within the app', async () => {
    const {user} = render(<TestButton path="/a" />, {wrapper: Wrapper})
    await user.click(screen.getByText('Navigate'))
    expect(navigateFn).toHaveBeenCalledWith('/a', {})
    expect(visit).not.toHaveBeenCalled()
  })

  it('navigates using Turbo for destinations outside the app', async () => {
    const {user} = render(<TestButton path="/b" />, {wrapper: Wrapper})
    await user.click(screen.getByText('Navigate'))
    expect(navigateFn).not.toHaveBeenCalled()
    await waitFor(() => expect(visit).toHaveBeenCalledWith('/b', {}))
  })

  it('navigates using Turbo for full url', async () => {
    const {user} = render(<TestButton path="https://github.com" />, {wrapper: Wrapper})
    await user.click(screen.getByText('Navigate'))
    expect(navigateFn).not.toHaveBeenCalled()
    await waitFor(() => expect(visit).toHaveBeenCalledWith('https://github.com', {}))
  })

  it('navigates using Turbo if reloadDocument is used', async () => {
    const {user} = render(<TestButtonWithReload path="/a" />, {wrapper: Wrapper})
    await user.click(screen.getByText('Navigate'))
    expect(navigateFn).not.toHaveBeenCalled()
    await waitFor(() => expect(visit).toHaveBeenCalledWith('/a', {}))
  })
})
