// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {IssueViewerContextProvider} from '@github-ui/issue-viewer/IssueViewerContextProvider'
import {RoutesContext} from '@github-ui/react-core/routes-context'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {renderHook} from '@testing-library/react'
import type React from 'react'
import {RelayEnvironmentProvider} from 'react-relay'
import {createSearchParams} from 'react-router-dom'
import {createMockEnvironment} from 'relay-test-utils'

import {useRouteInfo} from '../use-route-info'

const environment = createMockEnvironment()

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let urlParams: any = {}
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const searchParams: any = {}

jest.mock('react-router-dom', () => {
  const originalModule = jest.requireActual('react-router-dom')
  const navigateFn = jest.fn()
  return {
    ...originalModule,
    useNavigate: () => navigateFn,
    _routerNavigateFn: navigateFn,
    useSearchParams: () => [createSearchParams(searchParams), jest.fn()],
    useParams: () => urlParams,
  }
})

const Wrapper: React.FC<{children: React.ReactNode}> = ({children}) => {
  return (
    <RoutesContext.Provider
      value={{
        routes: [jsonRoute({path: '/a', Component: () => null})],
      }}
    >
      <RelayEnvironmentProvider environment={environment}>
        <IssueViewerContextProvider>{children}</IssueViewerContextProvider>
      </RelayEnvironmentProvider>
    </RoutesContext.Provider>
  )
}

beforeEach(() => {
  jest.clearAllMocks()
})

test('returns undefined values for route info on empty route', () => {
  const {result} = renderHook(() => useRouteInfo(), {wrapper: Wrapper})

  expect(result.current.itemIdentifier?.owner).toBeUndefined()
  expect(result.current.itemIdentifier?.repo).toBeUndefined()
  expect(result.current.itemIdentifier?.number).toBeUndefined()
})

test('returns route params for an issue', () => {
  urlParams = {
    owner: 'github',
    repo: 'issues',
    number: '1',
  }

  const {result} = renderHook(() => useRouteInfo(), {wrapper: Wrapper})

  expect(result.current.itemIdentifier?.owner).toBe('github')
  expect(result.current.itemIdentifier?.repo).toBe('issues')
  expect(result.current.itemIdentifier?.number).toBe(1)
})
