// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {act, renderHook} from '@testing-library/react'
import {useCampaignsParams} from '../../hooks/use-campaigns-params'
import {RoutesContext} from '@github-ui/react-core/routes-context'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {MemoryRouter} from 'react-router-dom'

const navigateFn = jest.fn()

jest.mock('react-router-dom', () => {
  const originalModule = jest.requireActual('react-router-dom')

  return {
    ...originalModule,
    useNavigate: () => navigateFn,
  }
})

beforeEach(() => {
  jest.clearAllMocks()
})

const render = (path: string) =>
  renderHook(() => useCampaignsParams(), {
    wrapper: ({children}) => (
      <RoutesContext.Provider
        value={{
          routes: [jsonRoute({path: '/test', Component: () => null})],
        }}
      >
        <MemoryRouter initialEntries={[path]} future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
          {children}
        </MemoryRouter>
      </RoutesContext.Provider>
    ),
  })

test('should return default data when there is nothing in the URL', () => {
  const {result} = render('/test')

  expect(result.current.campaignState).toEqual('open')
  expect(result.current.cursor).toBeNull()
})

test('should return the state from the URL', () => {
  const {result} = render('/test?state=closed')

  expect(result.current.campaignState).toEqual('closed')
})

test('should return the before cursor from the URL', () => {
  const {result} = render('/test?before=123')

  expect(result.current.cursor).toEqual({
    before: '123',
  })
})

test('should return the after cursor from the URL', () => {
  const {result} = render('/test?after=235')

  expect(result.current.cursor).toEqual({
    after: '235',
  })
})

test('should return the after cursor from the URL if both are given', () => {
  const {result} = render('/test?before=123&after=235')

  expect(result.current.cursor).toEqual({
    after: '235',
  })
})

test('should change the state and reset the cursor when calling onQueryChange', () => {
  const {result} = render('/test?state=open&after=123')

  expect(result.current.campaignState).toEqual('open')
  expect(result.current.cursor).toEqual({
    after: '123',
  })

  act(() => {
    result.current.onCampaignStateChange('closed')
  })

  expect(result.current.campaignState).toEqual('closed')
  expect(result.current.cursor).toBeNull()
  expect(navigateFn).toHaveBeenCalledTimes(1)
  expect(navigateFn).toHaveBeenCalledWith(
    {
      pathname: '/test',
      search: 'state=closed',
    },
    {},
  )
})

test('should change the cursor when calling onCursorChange', () => {
  const {result} = render('/test?state=open&after=123')

  expect(result.current.campaignState).toEqual('open')
  expect(result.current.cursor).toEqual({
    after: '123',
  })

  act(() => {
    result.current.onCursorChange({
      before: '456',
    })
  })

  expect(result.current.campaignState).toBe('open')
  expect(result.current.cursor).toEqual({
    before: '456',
  })
  expect(navigateFn).toHaveBeenCalledTimes(1)
  expect(navigateFn).toHaveBeenCalledWith(
    {
      pathname: '/test',
      search: 'state=open&before=456',
    },
    {},
  )
})

test('should return the open state for an arbitrary state from the URL', () => {
  const {result} = render('/test?state=abc')

  expect(result.current.campaignState).toBe('open')
})
