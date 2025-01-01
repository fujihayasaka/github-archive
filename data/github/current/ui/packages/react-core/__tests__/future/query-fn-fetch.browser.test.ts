import {afterEach, beforeAll, beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import {http, HttpResponse, msw} from '@github-ui/tests/msw'

import {queryFnFetch} from '../../future/query-fn-fetch'
import {ResponseError} from '../../future/response-error'

const reportTraceDataSpy = vi.fn()
const serverSpy = vi.fn()

vi.mock('../../../internal-api-insights/index', () => {
  return {
    reportTraceData: () => reportTraceDataSpy(),
  }
})

const jsonResponse = {field1: 'abc', field2: 'def'}

describe('queryFnFetch', () => {
  let baseUrl: string

  beforeAll(async () => {
    baseUrl = window.location.origin
  })
  beforeEach(() => {
    msw.use(
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
  })
  afterEach(() => {
    reportTraceDataSpy.mockClear()
    serverSpy.mockClear()
  })

  it('returns response.json', async () => {
    const expectedResponse = jsonResponse
    const actualResponse = await queryFnFetch({queryDeps: {pathname: '/path'}})
    expect(expectedResponse).toEqual(actualResponse)
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/path`)
  })

  it('reports trace data', async () => {
    await queryFnFetch({queryDeps: {pathname: '/path'}})
    expect(reportTraceDataSpy).toHaveBeenCalled()
  })

  it('throws on non-OK response', async () => {
    await expect(queryFnFetch({queryDeps: {pathname: '/path-with-error'}})).rejects.toThrow(ResponseError)
  })

  it('Serializes URLSearchParams to the request URL', async () => {
    const searchParams = new URLSearchParams({potato: 'latkes', shiitake: 'mushrooms'})
    const actualResponse = await queryFnFetch({queryDeps: {pathname: '/params', searchParams}})
    expect(actualResponse).toEqual({potato: 'latkes', shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params?potato=latkes&shiitake=mushrooms`)
  })
  it('Serializes string searchParams to the request URL', async () => {
    const searchParams = 'potato=latkes&shiitake=mushrooms'
    const actualResponse = await queryFnFetch({queryDeps: {pathname: '/params', searchParams}})
    expect(actualResponse).toEqual({potato: 'latkes', shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params?potato=latkes&shiitake=mushrooms`)
  })
  it('Serializes an entries map of search params to the request URL', async () => {
    const searchParams = [
      ['potato', 'latkes'],
      ['shiitake', 'mushrooms'],
    ]
    const actualResponse = await queryFnFetch({queryDeps: {pathname: '/params', searchParams}})
    expect(actualResponse).toEqual({potato: 'latkes', shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params?potato=latkes&shiitake=mushrooms`)
  })
  it('Serializes an record of search params to the request URL', async () => {
    const searchParams = {
      potato: 'latkes',
      shiitake: 'mushrooms',
    }
    const actualResponse = await queryFnFetch({queryDeps: {pathname: '/params', searchParams}})
    expect(actualResponse).toEqual({potato: 'latkes', shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params?potato=latkes&shiitake=mushrooms`)
  })
  it('Serializes URLSearchParams.entries to the request URL', async () => {
    const searchParams = new URLSearchParams({potato: 'latkes', shiitake: 'mushrooms'})
    const actualResponse = await queryFnFetch({
      queryDeps: {pathname: '/params', searchParams: Array.from(searchParams.entries())},
    })
    expect(actualResponse).toEqual({potato: 'latkes', shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params?potato=latkes&shiitake=mushrooms`)
  })
  it('handles no search params', async () => {
    const actualResponse = await queryFnFetch({queryDeps: {pathname: '/params', searchParams: undefined}})
    expect(actualResponse).toEqual({})
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params`)
  })
  it('handles null search params', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {
        pathname: '/params',
        // @ts-expect-error: searchParams cannot be null
        searchParams: null,
      },
    })
    expect(actualResponse).toEqual({})
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params`)
  })
  it('handles null search params record', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {pathname: '/params', searchParams: {potato: null, shiitake: 'mushrooms'}},
    })
    expect(actualResponse).toEqual({shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params?shiitake=mushrooms`)
  })
  it('handles all null search params record', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {pathname: '/params', searchParams: {potato: null, shiitake: null}},
    })
    expect(actualResponse).toEqual({})
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params`)
  })
  it('handles null search params array', async () => {
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
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params?shiitake=mushrooms`)
  })
  it('handles all null search params array', async () => {
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
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params`)
  })
  it('handles undefined search params record', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {
        pathname: '/params',
        // @ts-expect-error: searchParams cannot be undefined
        searchParams: {potato: undefined, shiitake: 'mushrooms'},
      },
    })
    expect(actualResponse).toEqual({shiitake: 'mushrooms'})
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params?shiitake=mushrooms`)
  })
  it('handles all undefined search params record', async () => {
    const actualResponse = await queryFnFetch({
      queryDeps: {
        pathname: '/params',
        // @ts-expect-error: searchParams cannot be undefined
        searchParams: {potato: undefined, shiitake: undefined},
      },
    })
    expect(actualResponse).toEqual({})
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params`)
  })
  it('handles undefined search params array', async () => {
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
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params?shiitake=mushrooms`)
  })
  it('handles all undefined search params array', async () => {
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
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/params`)
  })
})
