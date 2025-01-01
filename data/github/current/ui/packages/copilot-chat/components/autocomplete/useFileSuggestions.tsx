import type {Suggestion, Suggestions} from '@github-ui/inline-autocomplete/types'
import {useQuery} from '@github-ui/react-query'
import {useMemo} from 'react'

import {useFilterQuery} from '../../hooks/use-filter-query'
import {useRepositoryFilesQuery} from '../../hooks/use-repository-files-query'
import {useChatManager} from '../../utils/CopilotChatManagerContext'
import {ReferenceMention} from '../../utils/reference-mention'
import {FileSuggestion} from './FileSuggestion'

export interface FilesQuery {
  category: 'files'
  repository: string
  filter: string
}

export function useFilesSuggestions(query: FilesQuery | null) {
  const manager = useChatManager()

  const repoQuery = useQuery({
    enabled: query !== null,
    queryKey: ['copilot-repository', query?.repository],
    queryFn: async () => {
      if (!query?.repository) return null

      const response = await manager.service.fetchRepo(query?.repository)

      if (!response.ok) throw new Error('Failed to fetch repository')

      return response.payload
    },
    staleTime: 1000 * 60 * 5, // 5 minutes
  })

  const filesAndFoldersQuery = useRepositoryFilesQuery(repoQuery.data ?? null)

  const directoriesSet = useMemo(
    () => new Set(filesAndFoldersQuery.data?.directories ?? []),
    [filesAndFoldersQuery.data?.directories],
  )

  // Combining the files and folders allows for sorting together in a single list
  const filterQuery = useFilterQuery(
    filesAndFoldersQuery.data
      ? (filesAndFoldersQuery.data.paths ?? []).concat(filesAndFoldersQuery.data.directories ?? [])
      : null,
    query?.filter ?? '',
  )

  const suggestions = useMemo<Suggestions | null>(() => {
    if (!query) return null

    if (repoQuery.isLoading || filesAndFoldersQuery.isLoading || filterQuery.isLoading) return 'loading'

    const result = [
      ...(filterQuery.data?.slice(0, 5).map<Suggestion>(file => ({
        value: ReferenceMention.stringify({
          repo: query.repository,
          type: 'file',
          id: file,
        }),
        key: file,
        render: props => (
          <FileSuggestion
            {...props}
            path={file}
            type={directoriesSet.has(file) ? 'folder' : 'file'}
            stale={filterQuery.isPlaceholderData}
          />
        ),
      })) ?? []),
    ]

    return result.length > 0 ? result : null
  }, [
    directoriesSet,
    filterQuery.data,
    filterQuery.isLoading,
    filesAndFoldersQuery.isLoading,
    filterQuery.isPlaceholderData,
    query,
    repoQuery.isLoading,
  ])

  return {suggestions, stale: repoQuery.isPlaceholderData}
}
