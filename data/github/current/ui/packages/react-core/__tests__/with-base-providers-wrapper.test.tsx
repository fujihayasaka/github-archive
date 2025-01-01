// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {renderHook} from '@testing-library/react'
import {QueryClient, useQueryClient} from '@tanstack/react-query'
import {withBaseProvidersWrapper} from '../test-utils/Render'
import type {ReactNode} from 'react'
import {getQueryClient} from '../query-client'

const TestQueryClientProvider = ({children}: {children: ReactNode}) => {
  const client = useQueryClient()
  expect(client).toBeDefined()
  expect(client).toBeInstanceOf(QueryClient)
  return children
}

const useTestHook = () => {
  const client = useQueryClient()
  expect(client).toBeDefined()
  expect(client).toBeInstanceOf(QueryClient)
  return client.getQueryData(['test-value'])
}

const createInnerWrapper = ({children}: {children: ReactNode}) => {
  // Modifies the value of the query data to mimic inserting a new value
  const client = getQueryClient()
  client.setQueryData(['test-value'], 10)
  return <TestQueryClientProvider>{children}</TestQueryClientProvider>
}

describe('withBaseProvidersWrapper', () => {
  it('renders correctly with renderHook', () => {
    const wrapper = withBaseProvidersWrapper()
    const client = getQueryClient()
    client.setQueryData(['test-value'], 5)

    const {result} = renderHook(() => useTestHook(), {wrapper})

    expect(result.current).toBe(5)
  })

  it('renders correctly with renderHook and inner wrapper', () => {
    const wrapper = withBaseProvidersWrapper(createInnerWrapper)
    const {result} = renderHook(() => useTestHook(), {wrapper})

    expect(result.current).toBe(10)
  })
})
