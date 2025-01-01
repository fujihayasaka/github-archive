import {QueryCache, QueryClient} from '@github-ui/react-query'
// eslint-disable-next-line @github-ui/github-monorepo/prefer-github-ui-react-query, @github-ui/github-monorepo/no-query-client-provider
import {QueryClientProvider} from '@tanstack/react-query'
import {useRef, useState} from 'react'

import type {TTelemetryPropertyBag} from '../telemetry/interfaces'
import {useAnalytics} from '../telemetry/use-analytics'

export function ApiClientProvider(props: {children?: React.ReactNode}) {
  const sendEvent = useAnalytics()

  // The query client is only initialized once, but the `sendEvent` function might change
  // and we want to use the latest version of it when sending telemetry events.
  const sendEventWrapper = useRef(sendEvent)
  // eslint-disable-next-line react-compiler/react-compiler
  sendEventWrapper.current = sendEvent

  const [queryClient] = useState(
    () =>
      new QueryClient({
        queryCache: new QueryCache({
          onSuccess: (data, query) => {
            const context = query.meta as TTelemetryPropertyBag
            sendEventWrapper.current('react-query.success', context)
          },
          onError: (error, query) => {
            const context = query.meta as TTelemetryPropertyBag
            sendEventWrapper.current('react-query.error', {
              error_name: error.name,
              error_message: error.message,
              ...context,
            })
          },
        }),
      }),
  )
  return <QueryClientProvider client={queryClient}>{props.children}</QueryClientProvider>
}
