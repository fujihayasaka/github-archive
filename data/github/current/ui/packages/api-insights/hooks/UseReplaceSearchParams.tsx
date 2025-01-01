import {useSearchParams} from '@github-ui/use-navigate'
import {useCallback} from 'react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {PageParamsPayload} from './UseDefaultParams'

type ReplaceSearchParamFunction = (queryParam: string, value: string) => void
type ReplaceSearchParamsFunction = (params: Record<string, string>) => void

export function useReplaceSearchParams(): {
  replaceSearchParam: ReplaceSearchParamFunction
  replaceSearchParams: ReplaceSearchParamsFunction
  searchParams: URLSearchParams
} {
  const [searchParams, setSearchParams] = useSearchParams()
  const payload = useRoutePayload<PageParamsPayload>()
  const page_params = payload?.page_params
  return {
    replaceSearchParam: useCallback(
      (queryParam: string, value: string) => {
        setSearchParams(
          oldParams => {
            const used_params = page_params || oldParams
            const params = new URLSearchParams(used_params)
            if (value === '') {
              params.delete(queryParam)
            } else {
              params.set(queryParam, value)
            }
            return params
          },
          {
            preventAutofocus: true, // prevents scroll/focus reset to 0
          },
        )
      },
      [setSearchParams, page_params],
    ),
    replaceSearchParams: useCallback(
      (newParams: Record<string, string>) => {
        setSearchParams(
          oldParams => {
            const used_params = page_params || oldParams
            const params = new URLSearchParams(used_params)
            for (const [key, value] of Object.entries(newParams)) {
              if (value === '') {
                params.delete(key)
              } else {
                params.set(key, value)
              }
            }
            return params
          },
          {
            preventAutofocus: true, // prevents scroll/focus reset to 0
          },
        )
      },
      [setSearchParams, page_params],
    ),
    searchParams: new URLSearchParams(page_params || searchParams),
  }
}
