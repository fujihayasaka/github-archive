import {setupServer} from 'msw/node'
import {queryFnFetch} from '../../future/query-fn-fetch'
import {http, HttpResponse} from 'msw'
import {ResponseError} from '../../future/response-error'

const reportTraceDataSpy = jest.fn()
const serverSpy = jest.fn()

jest.mock('../../../internal-api-insights/index', () => {
  return {
    reportTraceData: () => reportTraceDataSpy(),
  }
})

const jsonResponse = {field1: 'abc', field2: 'def'}

const server = setupServer(
  http.get('/path', ({request}) => {
    serverSpy(request.url)
    return HttpResponse.json(jsonResponse)
  }),
  http.get('/path-with-error', ({request}) => {
    serverSpy(request.url)
    return new HttpResponse(null, {status: 500})
  }),
  http.get('/params', ({request}) => {
    serverSpy(request.url)
    const params = new URL(request.url, window.location.origin).searchParams
    return HttpResponse.json(Object.fromEntries(params))
  }),
)

describe('queryFnFetch', () => {
  beforeAll(() => server.listen())
  afterEach(() => {
    server.resetHandlers()
    reportTraceDataSpy.mockClear()
    serverSpy.mockClear()
  })
  afterAll(() => server.close())

  test('returns response.json', async () => {
    const expectedResponse = jsonResponse
    const actualResponse = await queryFnFetch({queryDeps: {pathname: '/path'}})
    expect(expectedResponse).toEqual(actualResponse)
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/path')
  })

  test('reports trace data', async () => {
    await queryFnFetch({queryDeps: {pathname: '/path'}})
    expect(reportTraceDataSpy).toHaveBeenCalled()
  })

  test('throws on non-OK response', async () => {
    await expect(queryFnFetch({queryDeps: {pathname: '/path-with-error'}})).rejects.toThrow(ResponseError)
  })

  test('Serializes URLSearchParams to the request URL', async () => {
    const searchParams = new URLSearchParams({potato: 'latkes', shiitake: 'mushrooms'})
    const actualResponse = await queryFnFetch({queryDeps: {pathname: '/params', searchParams}})
    expect(actualResponse).toEqual({potato: 'latkes', shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params?potato=latkes&shiitake=mushrooms')
  })
  test('Serializes string searchParams to the request URL', async () => {
    const searchParams = 'potato=latkes&shiitake=mushrooms'
    const actualResponse = await queryFnFetch({queryDeps: {pathname: '/params', searchParams}})
    expect(actualResponse).toEqual({potato: 'latkes', shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params?potato=latkes&shiitake=mushrooms')
  })
  test('Serializes an entries map of search params to the request URL', async () => {
    const searchParams = [
      ['potato', 'latkes'],
      ['shiitake', 'mushrooms'],
    ]
    const actualResponse = await queryFnFetch({queryDeps: {pathname: '/params', searchParams}})
    expect(actualResponse).toEqual({potato: 'latkes', shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params?potato=latkes&shiitake=mushrooms')
  })
  test('Serializes an record of search params to the request URL', async () => {
    const searchParams = {
      potato: 'latkes',
      shiitake: 'mushrooms',
    }
    const actualResponse = await queryFnFetch({queryDeps: {pathname: '/params', searchParams}})
    expect(actualResponse).toEqual({potato: 'latkes', shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params?potato=latkes&shiitake=mushrooms')
  })
  test('Serializes URLSearchParams.entries to the request URL', async () => {
    const searchParams = new URLSearchParams({potato: 'latkes', shiitake: 'mushrooms'})
    const actualResponse = await queryFnFetch({
      queryDeps: {pathname: '/params', searchParams: Array.from(searchParams.entries())},
    })
    expect(actualResponse).toEqual({potato: 'latkes', shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params?potato=latkes&shiitake=mushrooms')
  })
  test('handles no search params', async () => {
    const actualResponse = await queryFnFetch({queryDeps: {pathname: '/params', searchParams: undefined}})
    expect(actualResponse).toEqual({})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params')
  })
  test('handles null search params', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {
        pathname: '/params',
        // @ts-expect-error: searchParams cannot be null
        searchParams: null,
      },
    })
    expect(actualResponse).toEqual({})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params')
  })
  test('handles null search params record', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {pathname: '/params', searchParams: {potato: null, shiitake: 'mushrooms'}},
    })
    expect(actualResponse).toEqual({shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params?shiitake=mushrooms')
  })
  test('handles all null search params record', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {pathname: '/params', searchParams: {potato: null, shiitake: null}},
    })
    expect(actualResponse).toEqual({})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params')
  })
  test('handles null search params array', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {
        pathname: '/params',
        searchParams: [
          ['potato', null],
          ['shiitake', 'mushrooms'],
        ],
      },
    })
    expect(actualResponse).toEqual({shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params?shiitake=mushrooms')
  })
  test('handles all null search params array', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {
        pathname: '/params',
        searchParams: [
          ['potato', null],
          ['shiitake', null],
        ],
      },
    })
    expect(actualResponse).toEqual({})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params')
  })
  test('handles undefined search params record', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {
        pathname: '/params',
        // @ts-expect-error: searchParams cannot be undefined
        searchParams: {potato: undefined, shiitake: 'mushrooms'},
      },
    })
    expect(actualResponse).toEqual({shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params?shiitake=mushrooms')
  })
  test('handles all undefined search params record', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {
        pathname: '/params',
        // @ts-expect-error: searchParams cannot be undefined
        searchParams: {potato: undefined, shiitake: undefined},
      },
    })
    expect(actualResponse).toEqual({})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params')
  })
  test('handles undefined search params array', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {
        pathname: '/params',
        searchParams: [
          // @ts-expect-error: searchParams cannot be undefined
          ['potato', undefined],
          ['shiitake', 'mushrooms'],
        ],
      },
    })
    expect(actualResponse).toEqual({shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params?shiitake=mushrooms')
  })
  test('handles all undefined search params array', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {
        pathname: '/params',
        searchParams: [
          // @ts-expect-error: searchParams cannot be undefined
          ['potato', undefined],
          // @ts-expect-error: searchParams cannot be undefined
          ['shiitake', undefined],
        ],
      },
    })
    expect(actualResponse).toEqual({})
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/params')
  })
})
