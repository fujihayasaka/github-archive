import type {FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {pullRequestCopilotDiffChatPath} from '@github-ui/paths'
import {useSafeAsyncCallback} from '@github-ui/use-safe-async-callback'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useEffect, useState} from 'react'

// should only be used when useGetDiffEntryData encounters a 403, meaning the user does not have copilot chat access
export class GetDiffEntryDataForbiddenError extends Error {
  constructor(...args: ConstructorParameters<typeof Error>) {
    super(...args)
    this.name = 'GetDiffEntryDataForbiddenError'
  }
}

export interface DiffEntryData {
  path: string
  reference?: FileDiffReference
}

export interface useGetDiffEntryDataProps {
  owner: string
  repo: string
  number: number
  baseOid: string
  headOid: string
  filePath?: string
}

export const useGetDiffEntryData = (props: useGetDiffEntryDataProps) => {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<Error>()
  const [entriesData, setEntriesData] = useState<DiffEntryData[]>([])

  const fetchEntries = useSafeAsyncCallback(async (request_path: string, file_path?: string) => {
    setLoading(true)
    setError(undefined)

    try {
      const response = await verifiedFetch(request_path)

      if (response.status === 403) throw new GetDiffEntryDataForbiddenError()
      if (!response.ok) throw new Error(`Request failed: ${response.status}`)

      let data: DiffEntryData[] = await response.json()

      // filter by file_path if provided
      if (file_path) {
        data = []
        const singleEntry = data.find(entry => entry.path === file_path)
        if (singleEntry) data.push(singleEntry)
      }

      setEntriesData(data)
    } catch (err: Error | unknown) {
      setError(err instanceof Error ? err : new Error('unknown error'))
    }

    setLoading(false)
  })

  useEffect(() => {
    fetchEntries(pullRequestCopilotDiffChatPath(props), props.filePath)
  }, [props, fetchEntries])

  return {
    entriesData,
    loading,
    error,
  }
}
