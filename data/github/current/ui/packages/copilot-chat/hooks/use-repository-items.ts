import {getRepositorySearchQuery} from '@github-ui/issue-viewer/Queries'
import {
  RepositoryFragment,
  SearchRepositories,
  TopRepositories,
  TopRepositoriesFragment,
} from '@github-ui/item-picker/RepositoryPicker'
import type {
  RepositoryPickerRepository$data,
  RepositoryPickerRepository$key,
} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import type {
  RepositoryPickerSearchRepositoriesQuery,
  RepositoryPickerSearchRepositoriesQuery$data,
} from '@github-ui/item-picker/RepositoryPickerSearchRepositoriesQuery.graphql'
import type {RepositoryPickerTopRepositories$key} from '@github-ui/item-picker/RepositoryPickerTopRepositories.graphql'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import {useCallback, useEffect, useRef, useState} from 'react'
import {fetchQuery, readInlineData, useFragment, useRelayEnvironment} from 'react-relay'
import type {Subscription} from 'relay-runtime'

import type {CopilotChatRepo, TopicItem} from '../utils/copilot-chat-types'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'

export function useRepositoryItems(
  filterText: string,
  topRepositoryResults: RepositoryPickerTopRepositories$key | undefined,
  setTopRepositoryResults: (results: RepositoryPickerTopRepositories$key | undefined) => void,
  open: boolean,
  currentRepository?: CopilotChatRepo,
  topicDisplayCount?: number,
) {
  const {topRepositoriesCache} = useChatState()

  const chatManager = useChatManager()
  const [repositories, setRepositories] = useState<TopicItem[]>([])
  const [loading, setLoading] = useState<boolean>(!topRepositoriesCache)

  const searchedReposSubscription = useRef<Subscription | undefined>(undefined)
  const relayEnvironment = useRelayEnvironment()

  const topRepositoryFragment = useFragment<RepositoryPickerTopRepositories$key>(
    TopRepositoriesFragment,
    topRepositoryResults ?? null,
  )

  if (topRepositoryFragment && !topRepositoriesCache && !filterText) {
    const {topRepositories} = topRepositoryFragment

    const fetchedRepos = (topRepositories.edges || []).flatMap(a =>
      // eslint-disable-next-line no-restricted-syntax
      a?.node ? [readInlineData<RepositoryPickerRepository$key>(RepositoryFragment, a.node)] : [],
    )
    const topReposMapped = getListItemsFromRepos(fetchedRepos)

    const {ownerLogin, name} = currentRepository ?? {}
    if (
      currentRepository &&
      !topReposMapped.find(repo => `${repo.ownerLogin}/${repo.name}` === `${ownerLogin}/${name}`)
    ) {
      topReposMapped.splice(0, 0, {
        databaseId: currentRepository.id,
        isInOrganization: currentRepository.ownerType === 'Organization',
        name: currentRepository.name,
        nwo: `${currentRepository.ownerLogin}/${currentRepository.name}`,
        ownerLogin: currentRepository.ownerLogin,
        ownerAvatarUrl: `/${currentRepository.ownerLogin}.png?s=40`,
      })
    }
    // setTimeout to prevent a race condition and a warning from React
    // Update TopicList first with the top repositories and then update CopilotChatProvider
    setTimeout(() => chatManager.setTopRepositoryTopics(topReposMapped), 10)
    setLoading(false)
    // We already set the cache so reset the top repos so we stop calling Relay
    setTopRepositoryResults(undefined)
  }

  const fetchTopRepos = useCallback(async () => {
    try {
      const topRepos = await fetchQuery<RepositoryPickerTopRepositoriesQuery>(relayEnvironment, TopRepositories, {
        topRepositoriesFirst: topicDisplayCount,
      }).toPromise()
      setTopRepositoryResults(topRepos?.viewer)
    } catch {
      // If we have an error, just silently catch
      // We can't return because we want to use the useFragment hook
      // But we can check for null later
    } finally {
      setLoading(false)
    }
  }, [relayEnvironment, setTopRepositoryResults, topicDisplayCount])

  useEffect(() => {
    if (open) void fetchTopRepos()
  }, [fetchTopRepos, open])

  useEffect(() => {
    const fetchSearchedRepos = async (query: string) => {
      setLoading(true)
      const searchedRepos: RepositoryPickerSearchRepositoriesQuery$data = await new Promise((resolve, reject) => {
        fetchQuery<RepositoryPickerSearchRepositoriesQuery>(relayEnvironment, SearchRepositories, {
          searchQuery: getRepositorySearchQuery(query),
        }).subscribe({
          start: subscription => {
            searchedReposSubscription.current?.unsubscribe()
            searchedReposSubscription.current = subscription
          },
          next: data => {
            resolve(data)
          },
          error: (e: Error) => {
            reject(e)
          },
        })
      })

      const fetchedRepos = (searchedRepos.search.nodes || []).flatMap(node =>
        // eslint-disable-next-line no-restricted-syntax
        node ? [readInlineData<RepositoryPickerRepository$key>(RepositoryFragment, node)] : [],
      )

      setRepositories(fetchedRepos.length ? getListItemsFromRepos(fetchedRepos) : [])
      setLoading(false)
    }

    if (filterText) {
      void fetchSearchedRepos(filterText)
    } else if (topRepositoriesCache) {
      setRepositories(topRepositoriesCache)
    }
  }, [filterText, relayEnvironment, topRepositoriesCache])

  if (topRepositoriesCache && !filterText) {
    return {repositories: topRepositoriesCache, loading: false}
  }

  return {repositories, loading}
}

function getListItemsFromRepos(repos: RepositoryPickerRepository$data[]): TopicItem[] {
  return repos.map(({owner: {login, avatarUrl}, isInOrganization, name, databaseId}) => ({
    databaseId: databaseId ?? 0,
    isInOrganization,
    name,
    nwo: `${login}/${name}`,
    ownerLogin: login,
    ownerAvatarUrl: avatarUrl,
  }))
}
