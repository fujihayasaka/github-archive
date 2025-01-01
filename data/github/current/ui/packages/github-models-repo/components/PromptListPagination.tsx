import {useCallback, useEffect, useState} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'
import {repoModelsPath} from '@github-ui/paths'
import {Pagination, Stack} from '@primer/react'
import type {Repository} from '@github-ui/current-repository'
import type {ParsedPrompt} from '../types'
import {usePromptsQuery} from '../hooks/use-prompts-query'

interface PromptListPaginationProps {
  repository: Pick<Repository, 'ownerLogin' | 'name'>
  page: number
  totalPages: number
  onPromptsLoaded: (promptsInPage: ParsedPrompt[], newPage: number) => void
}

export function PromptListPagination({
  page: initialPage,
  totalPages,
  onPromptsLoaded,
  repository: {ownerLogin, name},
}: PromptListPaginationProps) {
  const [page, setPage] = useState(initialPage)
  const [_, setSearchParams] = useSearchParams()
  const buildPageUrl = useCallback(
    (pageNum: number) => {
      const basePath = repoModelsPath({repo: {ownerLogin, name}, action: 'prompts'})
      if (pageNum === 1) return basePath
      return `${basePath}?page=${pageNum}`
    },
    [ownerLogin, name],
  )
  const updatePageInUrl = useCallback(
    (newPage: number) => {
      if (newPage === 1) {
        setSearchParams(prev => {
          const newParams = new URLSearchParams(prev)
          newParams.delete('page')
          return newParams
        })
      } else {
        setSearchParams(prev => ({...prev, page: newPage.toString()}))
      }
    },
    [setSearchParams],
  )
  const {data, isPlaceholderData} = usePromptsQuery(ownerLogin, name, page === initialPage ? 0 : page)

  useEffect(() => {
    if (data && !isPlaceholderData) {
      onPromptsLoaded(data.prompts, data.page)
      updatePageInUrl(data.page)
    }
  }, [data, isPlaceholderData, onPromptsLoaded, updatePageInUrl])

  if (totalPages < 2) return null

  return (
    <Stack.Item className="Box-row py-0">
      <Pagination
        hrefBuilder={buildPageUrl}
        pageCount={totalPages}
        currentPage={page}
        onPageChange={(event, newPage) => {
          event.preventDefault()
          setPage(newPage)
        }}
      />
    </Stack.Item>
  )
}
