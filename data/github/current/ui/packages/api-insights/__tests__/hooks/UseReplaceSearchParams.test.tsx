import {useReplaceSearchParams} from '../../hooks/UseReplaceSearchParams'
import {screen} from '@testing-library/react'
import {render, RouteContext} from '@github-ui/react-core/test-utils'
import {getPageParamsPayload} from '../../test-utils/mock-data'

const TestButton = ({queryParam, value}: {queryParam: string; value: string}) => {
  const {searchParams, replaceSearchParam} = useReplaceSearchParams()
  return <button onClick={() => replaceSearchParam(queryParam, value)}>{searchParams.toString()}</button>
}

const TestButtonMany = ({payload}: {payload: Record<string, string>}) => {
  const {searchParams, replaceSearchParams} = useReplaceSearchParams()
  return <button onClick={() => replaceSearchParams(payload)}>{searchParams.toString()}</button>
}

describe('replaceSearchParam', () => {
  test('updates the query param and makes search params available', async () => {
    const {user} = render(<TestButton queryParam="foo" value="bar" />, {
      pathname: '/donut',
      search: '?foo=baz&a=b',
    })
    const button = screen.getByRole('button')

    expect(RouteContext.location?.pathname).toEqual('/donut')
    expect(RouteContext.location?.search).toEqual('?foo=baz&a=b')

    expect(button).toHaveTextContent('foo=baz&a=b')

    await user.click(button)

    expect(RouteContext.location?.pathname).toEqual('/donut')
    expect(RouteContext.location?.search).toEqual('?foo=bar&a=b')
  })

  test('removes query parameter if value is empty string', async () => {
    const {user} = render(<TestButton queryParam="foo" value="" />, {
      pathname: '/donut',
      search: '?foo=baz&a=b',
    })
    const button = screen.getByRole('button')

    expect(RouteContext.location?.pathname).toEqual('/donut')
    expect(RouteContext.location?.search).toEqual('?foo=baz&a=b')

    expect(button).toHaveTextContent('foo=baz&a=b')

    await user.click(button)

    expect(RouteContext.location?.pathname).toEqual('/donut')
    expect(RouteContext.location?.search).toEqual('?a=b')
  })

  test('uses validated search params if available', async () => {
    const {user} = render(<TestButton queryParam="type" value="all" />, {
      pathname: '/api-insights',
      search: '?foo=baz&a=b',
      routePayload: getPageParamsPayload(),
    })
    const button = screen.getByRole('button')

    expect(RouteContext.location?.pathname).toEqual('/api-insights')
    expect(RouteContext.location?.search).toEqual('?foo=baz&a=b')

    expect(button).toHaveTextContent(
      'q=foo&p=2&n=asc&tr=asc&rlr=asc&lrl=asc&period=7d&interval=3h&type=apps&requests=rate&t=UTC',
    )

    await user.click(button)

    expect(RouteContext.location?.pathname).toEqual('/api-insights')
    expect(RouteContext.location?.search).toEqual(
      '?q=foo&p=2&n=asc&tr=asc&rlr=asc&lrl=asc&period=7d&interval=3h&type=all&requests=rate&t=UTC',
    )
  })
})

describe('replaceSearchParams', () => {
  test('updates multiple query params and makes search params available', async () => {
    const {user} = render(<TestButtonMany payload={{foo: 'bar', a: 'a', cat: 'kitty'}} />, {
      pathname: '/donut',
      search: '?foo=baz&a=b',
    })
    const button = screen.getByRole('button')

    expect(RouteContext.location?.pathname).toEqual('/donut')
    expect(RouteContext.location?.search).toEqual('?foo=baz&a=b')

    expect(button).toHaveTextContent('foo=baz&a=b')

    await user.click(button)

    expect(RouteContext.location?.pathname).toEqual('/donut')
    expect(RouteContext.location?.search).toEqual('?foo=bar&a=a&cat=kitty')
  })

  test('removes query parameter if value is empty string', async () => {
    const {user} = render(<TestButtonMany payload={{foo: 'bar', a: '', cat: 'kitty'}} />, {
      pathname: '/donut',
      search: '?foo=baz&a=b',
    })
    const button = screen.getByRole('button')

    expect(RouteContext.location?.pathname).toEqual('/donut')
    expect(RouteContext.location?.search).toEqual('?foo=baz&a=b')

    expect(button).toHaveTextContent('foo=baz&a=b')

    await user.click(button)

    expect(RouteContext.location?.pathname).toEqual('/donut')
    expect(RouteContext.location?.search).toEqual('?foo=bar&cat=kitty')
  })

  test('uses validated search params if available', async () => {
    const {user} = render(<TestButtonMany payload={{type: 'all', a: 'a', cat: 'kitty'}} />, {
      pathname: '/api-insights',
      search: '?foo=baz&a=b',
      routePayload: getPageParamsPayload(),
    })
    const button = screen.getByRole('button')

    expect(RouteContext.location?.pathname).toEqual('/api-insights')
    expect(RouteContext.location?.search).toEqual('?foo=baz&a=b')

    expect(button).toHaveTextContent(
      'q=foo&p=2&n=asc&tr=asc&rlr=asc&lrl=asc&period=7d&interval=3h&type=apps&requests=rate&t=UTC',
    )

    await user.click(button)

    expect(RouteContext.location?.pathname).toEqual('/api-insights')
    expect(RouteContext.location?.search).toEqual(
      '?q=foo&p=2&n=asc&tr=asc&rlr=asc&lrl=asc&period=7d&interval=3h&type=all&requests=rate&t=UTC&a=a&cat=kitty',
    )
  })
})
