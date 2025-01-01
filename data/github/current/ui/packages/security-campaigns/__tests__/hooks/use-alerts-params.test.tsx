import {act, renderHook} from '@testing-library/react'
import {MemoryRouter} from 'react-router-dom'
import {AppContext} from '@github-ui/react-core/app-context'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {useAlertsParams} from '../../hooks/use-alerts-params'

const navigateFn = jest.fn()

jest.mock('react-router-dom', () => {
  const originalModule = jest.requireActual('react-router-dom')

  return {
    ...originalModule,
    useNavigate: () => navigateFn,
  }
})

beforeAll(() => {
  performance.clearResourceTimings = jest.fn()
  performance.mark = jest.fn()
})

beforeEach(() => {
  jest.clearAllMocks()
})

const render = (path: string) =>
  renderHook(() => useAlertsParams(), {
    wrapper: ({children}) => (
      <AppContext.Provider
        value={{
          routes: [jsonRoute({path: '/test', Component: () => null})],
        }}
      >
        <MemoryRouter initialEntries={[path]} future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
          {children}
        </MemoryRouter>
      </AppContext.Provider>
    ),
  })

test('should return default data when there is no query in the URL', () => {
  const {result} = render('/test')

  // Ignore the functions that are returned
  const {onQueryChange, onCursorChange, onGroupChange, ...rest} = result.current

  expect(rest).toEqual({
    query: 'is:open',
    cursor: null,
    group: 'repository',
  })
})

test('should return the query from the URL', () => {
  const {result} = render('/test?query=is%3Aopen+resolution%3Adismissed+foo')

  expect(result.current.query).toBe('is:open resolution:dismissed foo')
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

test('should return the repository group from the URL', () => {
  const {result} = render('/test?group=repository')

  expect(result.current.group).toBe('repository')
})

test('should return the none group from the URL', () => {
  const {result} = render('/test?group=none')

  expect(result.current.group).toBe('none')
})

test('should return the repository group for an arbitrary group from the URL', () => {
  const {result} = render('/test?group=foobar')

  expect(result.current.group).toBe('repository')
})

test('should change the query and reset the cursor when calling onQueryChange', () => {
  const {result} = render('/test?query=is%3Aopen+resolution%3Adismissed+foo&after=123')

  expect(result.current.query).toBe('is:open resolution:dismissed foo')
  expect(result.current.cursor).toEqual({
    after: '123',
  })

  act(() => {
    result.current.onQueryChange('is:closed')
  })

  expect(result.current.query).toBe('is:closed')
  expect(result.current.cursor).toBe(null)
  expect(navigateFn).toHaveBeenCalledWith(
    {
      pathname: '/test',
      search: 'query=is%3Aclosed',
    },
    {},
  )
})

test('should change the cursor when calling onCursorChange', () => {
  const {result} = render('/test?query=is%3Aopen+resolution%3Adismissed+foo&after=123')

  expect(result.current.query).toBe('is:open resolution:dismissed foo')
  expect(result.current.cursor).toEqual({
    after: '123',
  })

  act(() => {
    result.current.onCursorChange({
      before: '456',
    })
  })

  expect(result.current.query).toBe('is:open resolution:dismissed foo')
  expect(result.current.cursor).toEqual({
    before: '456',
  })
  expect(navigateFn).toHaveBeenCalledWith(
    {
      pathname: '/test',
      search: 'query=is%3Aopen+resolution%3Adismissed+foo&before=456',
    },
    {},
  )
})

test('should change the group and reset the cursor when calling onGroupChange', () => {
  const {result} = render('/test?query=is%3Aopen+resolution%3Adismissed+foo&after=123')

  expect(result.current.query).toBe('is:open resolution:dismissed foo')
  expect(result.current.cursor).toEqual({
    after: '123',
  })
  expect(result.current.group).toEqual('repository')

  act(() => {
    result.current.onGroupChange('none')
  })

  expect(result.current.query).toBe('is:open resolution:dismissed foo')
  expect(result.current.cursor).toEqual(null)
  expect(result.current.group).toEqual('none')
  expect(navigateFn).toHaveBeenCalledWith(
    {
      pathname: '/test',
      search: 'query=is%3Aopen+resolution%3Adismissed+foo&group=none',
    },
    {},
  )
})
