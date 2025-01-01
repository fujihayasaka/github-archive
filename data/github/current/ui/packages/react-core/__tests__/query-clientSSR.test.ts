/** @jest-environment node */

import {QueryClient} from '@tanstack/react-query'
import {getQueryClient} from '../query-client'

test("Returns a new instance of queryClient on every call on the server to ensure that data isn't stored in a global cache that may potentially leak it", () => {
  const queryClient = getQueryClient()

  expect(queryClient).toBeInstanceOf(QueryClient)

  const queryClient2 = getQueryClient()
  expect(queryClient2).toBeInstanceOf(QueryClient)
  expect(queryClient).not.toBe(queryClient2)
})
