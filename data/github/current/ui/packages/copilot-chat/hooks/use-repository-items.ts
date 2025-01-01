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

import type {TopicItem} from '../utils/copilot-chat-types'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {getRepositoryFromOrgSearchQuery} from '../utils/custom-copilots-helpers'

export function useRepositoryItems(
  filterText: string,
  open: boolean,
  topicDisplayCount?: number,
  ownerDisplayLogin?: string,
) {
  const [topRepositoryResults, setTopRepositoryResults] = useState<RepositoryPickerTopRepositories$key | undefined>(
    undefined,
  )
  const resetTopRepoResults = useCallback(() => setTopRepositoryResults(undefined), [])

  const {topRepositoriesCache, currentRepository} = useChatState()

  const chatManager = useChatManager()
  const [repositories, setRepositories] = useState<TopicItem[]>([])
  const [loading, setLoading] = useState<true | false | 'initial'>(!topRepositoriesCache ? 'initial' : false)

  const searchedReposSubscription = useRef<Subscription | undefined>(undefined)
  const relayEnvironment = useRelayEnvironment()

  const topRepositoryFragment = useFragment<RepositoryPickerTopRepositories$key>(
    TopRepositoriesFragment,
    topRepositoryResults ?? null,
  )

  // Currently only used by Spaces to filter repositories by the owner for org-owned spaces.
  const isOrgOwned = ownerDisplayLogin && ownerDisplayLogin.trim() !== ''

  if (topRepositoryFragment && !topRepositoriesCache && !filterText && !isOrgOwned) {
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
        owner: isOrgOwned ? ownerDisplayLogin : null,
      }).toPromise()
      setTopRepositoryResults(topRepos?.viewer)
    } catch {
      // If we have an error, just silently catch
      // We can't return because we want to use the useFragment hook
      // But we can check for null later
    } finally {
      setLoading(false)
    }
  }, [isOrgOwned, ownerDisplayLogin, relayEnvironment, setTopRepositoryResults, topicDisplayCount])

  useEffect(() => {
    if (open && !isOrgOwned) void fetchTopRepos()
  }, [fetchTopRepos, isOrgOwned, open, ownerDisplayLogin])

  useEffect(() => {
    const fetchSearchedRepos = async (query: string) => {
      setLoading(true)
      const searchedRepos: RepositoryPickerSearchRepositoriesQuery$data = await new Promise((resolve, reject) => {
        fetchQuery<RepositoryPickerSearchRepositoriesQuery>(relayEnvironment, SearchRepositories, {
          searchQuery: isOrgOwned
            ? getRepositoryFromOrgSearchQuery(ownerDisplayLogin, query)
            : getRepositorySearchQuery(query),
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

    if (filterText || isOrgOwned) {
      void fetchSearchedRepos(filterText)
    } else if (topRepositoriesCache) {
      setRepositories(topRepositoriesCache)
    }
  }, [filterText, isOrgOwned, ownerDisplayLogin, relayEnvironment, topRepositoriesCache])

  // Refresh list of top repositories based on the selected owner
  useEffect(() => {
    chatManager.setTopRepositoryTopics(undefined)
  }, [chatManager, ownerDisplayLogin])

  // If org owned, but no top repositories, just return repos from that org
  if (topRepositoriesCache && !filterText && !isOrgOwned) {
    return {repositories: topRepositoriesCache, loading: false, resetTopRepoResults}
  }

  return {repositories, loading, resetTopRepoResults}
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
