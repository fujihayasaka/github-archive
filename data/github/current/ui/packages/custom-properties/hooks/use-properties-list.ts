import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useCallback, useState} from 'react'

import {useListPropertiesPath} from './use-properties-paths'

interface Props<T> {
  initialPayload: T
}

export function usePropertiesListResults<T>({initialPayload}: Props<T>) {
  const path = useListPropertiesPath()

  const [currentPage, setCurrentPage] = useState(1)
  const [payload, setPayload] = useState(initialPayload)

  const fetchResults = useCallback(
    async ({page, filterQuery}: {page: string | number; filterQuery: string}) => {
      setCurrentPage(Number(page))

      const fetchParams = new URLSearchParams({page: page.toString(), q: filterQuery})
      const fetchUrl = `${path}?${fetchParams.toString()}`

      try {
        const response = await verifiedFetchJSON(fetchUrl)
        const data = (await response.json()) as {payload: T}
        setPayload(data.payload)
        window.scrollTo({top: 0})
      } catch {
        // Do nothing
      }
    },
    [setCurrentPage, path],
  )

  return {currentPage, payload, fetchResults}
}
