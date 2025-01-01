import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {sendStats} from '@github-ui/stats'

const globalFetch = fetch

export default function applyFetchPatch() {
  if (ssrSafeWindow) {
    ssrSafeWindow.fetch = async (input: string | URL | Request, init?: RequestInit) => {
      try {
        const response = await globalFetch(input, init)
        sendFetchStats({input, error: !response.ok, status: response.status})
        return response
      } catch (error) {
        sendFetchStats({input, error: true, status: 'unknown'})
        throw error
      }
    }
  }
}

function sendFetchStats({
  input,
  error,
  status,
}: {
  input: string | URL | Request
  error: boolean
  status: number | string
}) {
  if (!error) return

  const url = input instanceof Request ? input.url : input.toString()
  sendStats(
    {
      incrementKey: 'FETCH_ERROR',
      requestUrl: window.location.href,
      referredRequestUrl: url,
      incrementTags: {
        status: String(status),
      },
    },
    false,
    1,
  )
}
