// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {expect, it} from '@github-ui/tests'
import {QueryClient} from '@tanstack/react-query'

import {getQueryClient} from '../query-client'

it('Returns a single instance of queryClient on every call on the server', () => {
  const queryClient = getQueryClient()
  expect(queryClient).toBeInstanceOf(QueryClient)
  expect(queryClient).toBe(getQueryClient())
})
