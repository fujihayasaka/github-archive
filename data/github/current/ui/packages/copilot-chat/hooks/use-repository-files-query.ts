import {useQuery} from '@github-ui/react-query'

import type {CopilotChatRepo} from '../utils/copilot-chat-types'
import {useChatManager} from '../utils/CopilotChatManagerContext'

export function useRepositoryFilesQuery(repository: CopilotChatRepo | null, includeDirectories = true) {
  const manager = useChatManager()

  return useQuery({
    enabled: repository !== null,
    queryKey: ['copilot-repository-files', repository, includeDirectories],
    queryFn: async () => {
      if (!repository) return {}

      const response = await manager.service.listRepoFiles(repository, includeDirectories)

      if (!response.ok) throw new Error('Failed to fetch files for repository')

      return response.payload
    },
    // this is an expensive request for large repos, so let's cache it for a while
    staleTime: 1000 * 60 * 5, // 5 minutes
  })
}
