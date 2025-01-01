import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {referenceID} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {useQuery} from '@github-ui/react-query'
import {useEffect} from 'react'

import type {File} from '../components/ContentPreview/content-preview-types'
import type {ContentPreviewContext} from '../components/ContentPreview/ContentPreviewContext'

/**
 * If the given file comes from a reference and has no content, will attempt to retrieve that content.
 */
export function useHydrateReference(file: File, updateItem: ContentPreviewContext['updateItem']) {
  const {reference} = file
  const manager = useChatManager()
  const {isLoading, isError, data} = useQuery({
    // eslint-disable-next-line @tanstack/query/exhaustive-deps
    queryKey: [
      'copilot-reference-preview',
      'copilot',
      'references',
      reference?.type,
      reference ? referenceID(reference) : undefined,
    ],
    queryFn: async () => {
      if (!reference || reference.type !== 'file' || !!file.value) return null

      const result = await manager.service.hydrateReference(reference)
      if (!result.ok) return null

      updateItem({...file, value: result.payload.contents, isStreaming: false})

      return result.payload
    },
    // references include an OID and are thus not going to change ever
    staleTime: Number.POSITIVE_INFINITY,
  })

  useEffect(() => {
    // if the query is cached we might still need to run updateItem
    if (data?.contents && file.value !== data.contents) {
      updateItem({...file, value: data.contents, isStreaming: false})
    }
  }, [data?.contents, file, updateItem])

  return {isLoading, isError, data}
}
