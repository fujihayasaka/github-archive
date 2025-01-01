import {useQuery} from '@github-ui/react-query'

import type {CopilotChatRepo} from '../utils/copilot-chat-types'
import {useChatManager} from '../utils/CopilotChatManagerContext'

/**
 * Fetches symbols from a repository based on a search query, will only fetch if
 * the repository is not null and the search query is not empty.
 */
export function useRepositorySymbolsQuery(repository: CopilotChatRepo | null, searchQuery: string) {
  const manager = useChatManager()
  return useQuery({
    enabled: repository !== null && searchQuery.length > 0,
    queryKey: ['copilot-repository-symbols', repository, searchQuery],
    queryFn: async () => {
      if (!repository) return []
      const response = await manager.service.querySymbols(repository, searchQuery)

      if (!response.ok) throw new Error('Failed to fetch symbols for repository')

      return response.payload.filter(symbol => Boolean(symbol.symbol))
    },
  })
}
