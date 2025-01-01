import {QueryClient} from '@tanstack/react-query'
import {getQueryClient} from '../query-client'

test('Returns the same instance of queryClient on every call on a browser', () => {
  const queryClient = getQueryClient()

  expect(queryClient).toBeInstanceOf(QueryClient)

  const queryClient2 = getQueryClient()
  expect(queryClient2).toBeInstanceOf(QueryClient)
  expect(queryClient).toBe(queryClient2)
})
