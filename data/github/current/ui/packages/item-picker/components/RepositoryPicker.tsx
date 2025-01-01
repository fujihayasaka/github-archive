/* eslint eslint-comments/no-use: off */
/* eslint-disable relay/unused-fields */
import {useDebounce} from '@github-ui/use-debounce'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {LockIcon, RepoIcon, TriangleDownIcon} from '@primer/octicons-react'
import {Box, Button, type SelectPanelProps} from '@primer/react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {
  fetchQuery,
  graphql,
  type PreloadedQuery,
  readInlineData,
  usePreloadedQuery,
  useRelayEnvironment,
  useFragment,
  type Environment,
} from 'react-relay'

import {ERRORS} from '../constants/errors'
import {LABELS} from '../constants/labels'
import type {
  RepositoryPickerRepository$data,
  RepositoryPickerRepository$key,
  RepositoryVisibility,
} from './__generated__/RepositoryPickerRepository.graphql'
import type {
  RepositoryPickerSearchRepositoriesQuery,
  RepositoryPickerSearchRepositoriesQuery$data,
} from './__generated__/RepositoryPickerSearchRepositoriesQuery.graphql'
import type {RepositoryPickerTopRepositoriesQuery} from './__generated__/RepositoryPickerTopRepositoriesQuery.graphql'
import {type ExtendedItemProps, ItemPicker} from './ItemPicker'
import {getRepositorySearchQuery} from '../shared'
import type {RepositoryPickerTopRepositories$key} from './__generated__/RepositoryPickerTopRepositories.graphql'
import type {RepositoryPickerCurrentRepoQuery} from './__generated__/RepositoryPickerCurrentRepoQuery.graphql'
import {VALUES} from '../constants/values'
import type {
  RepositoryPickerPossibleTransferRepositoriesQuery,
  RepositoryPickerPossibleTransferRepositoriesQuery$data,
} from './__generated__/RepositoryPickerPossibleTransferRepositoriesQuery.graphql'

export type Repository = RepositoryPickerRepository$data

type RepositoryPickerBaseProps = {
  initialRepository: Repository | undefined
  onSelect: (repo: Repository | undefined) => void
  preventDefault?: boolean
  organization?: string
  focusRepositoryPicker?: boolean
  enforceAtleastOneSelected?: boolean
  options?: {hasIssuesEnabled?: boolean; readonly?: boolean; includeForks?: boolean}
  renderTrailingVisual?: (repoId: string) => JSX.Element | undefined
  exclude?: string
  'aria-labelledby'?: string
  'aria-describedby'?: string
  anchorElement?: (props: React.HTMLAttributes<HTMLElement>) => JSX.Element
  title?: string
  subtitle?: string | React.ReactElement
  preventClose?: boolean
  triggerOpen?: boolean
  onOpen?: () => void
  onClose?: () => void
  ignoredRepositories?: string[]
  repositoryFilter?: (repo: Repository) => boolean
  customNoResultsTitle?: string
  customNoResultsItem?: JSX.Element
  repoNameOnly?: boolean
  pickerId?: string
  currentRepoVisibility?: RepositoryVisibility
  // We need this optional prop to pass the issue ID from the issue transfer dialog so we can query the possible repositories to transfer the issue to.
  issueId?: string
  // temporary, this will go away when fully ship the primer_react_select_panel_fullscreen_on_narrow FF
  responsiveOnNarrow?: boolean
  portalContainerName?: string
}

export type RepositoryPickerProps = RepositoryPickerBaseProps & {
  topReposQueryRef: PreloadedQuery<RepositoryPickerTopRepositoriesQuery>
}

type RepositoryPickerInternalProps = RepositoryPickerBaseProps & {
  topRepositoriesData: RepositoryPickerTopRepositories$key | null
}

export const CurrentRepository = graphql`
  query RepositoryPickerCurrentRepoQuery($owner: String!, $name: String!) {
    repository(owner: $owner, name: $name) {
      ...RepositoryPickerRepository
    }
  }
`

export const prefetchCurrentRepository = (environment: Environment, owner = '', name = '') => {
  return fetchQuery<RepositoryPickerCurrentRepoQuery>(
    environment,
    CurrentRepository,
    {
      owner,
      name,
    },
    {fetchPolicy: 'store-or-network'},
  )
}

export const TopRepositories = graphql`
  query RepositoryPickerTopRepositoriesQuery(
    $topRepositoriesFirst: Int = 10
    $hasIssuesEnabled: Boolean
    $owner: String = null
  ) {
    viewer {
      ...RepositoryPickerTopRepositories
        @arguments(topRepositoriesFirst: $topRepositoriesFirst, hasIssuesEnabled: $hasIssuesEnabled, owner: $owner)
    }
  }
`

export const TopRepositoriesFragment = graphql`
  fragment RepositoryPickerTopRepositories on User
  @argumentDefinitions(
    topRepositoriesFirst: {type: "Int", defaultValue: 10}
    hasIssuesEnabled: {type: "Boolean", defaultValue: true}
    owner: {type: "String", defaultValue: null}
  ) {
    topRepositories(
      first: $topRepositoriesFirst
      hasIssuesEnabled: $hasIssuesEnabled
      orderBy: {field: UPDATED_AT, direction: DESC}
      owner: $owner
    ) {
      edges {
        node {
          ...RepositoryPickerRepository
        }
      }
    }
  }
`

export const prefetchTopRepositories = (
  environment: Environment,
  first = 10,
  hasIssuesEnabled: boolean | undefined = undefined,
) => {
  return fetchQuery<RepositoryPickerTopRepositoriesQuery>(
    environment,
    TopRepositories,
    {
      topRepositoriesFirst: first,
      hasIssuesEnabled,
    },
    {fetchPolicy: 'store-or-network'},
  )
}

export const SearchRepositories = graphql`
  query RepositoryPickerSearchRepositoriesQuery($searchQuery: String!, $after: String) {
    search(query: $searchQuery, type: REPOSITORY, first: 10, after: $after) {
      repositoryCount
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        ... on Repository {
          ...RepositoryPickerRepository @dangerously_unaliased_fixme
        }
      }
    }
  }
`

const PossibleTransferRepositories = graphql`
  query RepositoryPickerPossibleTransferRepositoriesQuery($searchQuery: String, $issueId: ID!) {
    node(id: $issueId) {
      ... on Issue {
        possibleTransferRepositoriesForViewer(first: 10, query: $searchQuery) {
          edges {
            node {
              ...RepositoryPickerRepository
            }
          }
        }
      }
    }
  }
`

export const RepositoryFragment = graphql`
  fragment RepositoryPickerRepository on Repository @inline {
    id
    databaseId
    name
    nameWithOwner
    owner {
      databaseId
      login
      avatarUrl(size: 64)
      issueTypesEnabled
    }
    isPrivate
    visibility
    isArchived
    isInOrganization
    hasIssuesEnabled
    slashCommandsEnabled
    viewerCanPush
    isBlankIssuesEnabled
    viewerInteractionLimitReasonHTML(action: "create an issue")
    viewerIssueCreationPermissions {
      labelable
      milestoneable
      assignable
      triageable
      typeable
    }
    securityPolicyUrl
    contributingFileUrl
    codeOfConductFileUrl
    supportFileUrl
    shortDescriptionHTML
    planFeatures {
      maximumAssignees
    }
  }
`

export const RepositoryPickerPlaceholder = () => (
  <Button leadingVisual={RepoIcon} trailingVisual={TriangleDownIcon} disabled>
    {LABELS.selectRepository}
  </Button>
)

export function RepositoryPicker({topReposQueryRef, ...rest}: RepositoryPickerProps) {
  const preloadedData = usePreloadedQuery<RepositoryPickerTopRepositoriesQuery>(TopRepositories, topReposQueryRef)
  return preloadedData.viewer ? <RepositoryPickerInternal {...rest} topRepositoriesData={preloadedData.viewer} /> : null
}

export function RepositoryPickerInternal({
  initialRepository,
  onSelect,
  preventDefault,
  organization,
  topRepositoriesData,
  focusRepositoryPicker,
  enforceAtleastOneSelected,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  options: {hasIssuesEnabled, readonly, includeForks} = {
    hasIssuesEnabled: undefined,
    readonly: false,
    includeForks: false,
  },
  renderTrailingVisual,
  exclude,
  'aria-labelledby': ariaLabelledBy,
  'aria-describedby': ariaDescribedBy,
  anchorElement,
  title,
  subtitle,
  preventClose,
  triggerOpen,
  onOpen,
  onClose,
  ignoredRepositories,
  repositoryFilter,
  customNoResultsItem,
  customNoResultsTitle,
  repoNameOnly,
  pickerId,
  currentRepoVisibility,
  issueId,
  responsiveOnNarrow,
  portalContainerName,
}: RepositoryPickerInternalProps) {
  const {addToast} = useToastContext()
  const [initiallySelectedRepo, _] = useState<Repository | undefined>(initialRepository)
  const [filter, setFilter] = useState('')
  const [searchResults, setSearchResults] = useState<Repository[] | undefined>(undefined)
  const [searchLoading, setSearchLoading] = useState<boolean>(topRepositoriesData == null)
  // // We need to keep track of the filter value in a ref because the subscribe function captures the filter value at the time of creation and doesn't update when the state changes.
  const filterRef = useRef(filter)

  // Clear loading after initial data preloaded
  useEffect(() => {
    if (topRepositoriesData != null) {
      setSearchLoading(false)
    }
  }, [topRepositoriesData])

  const relayEnvironment = useRelayEnvironment()
  const fetchPossibleTransferRepos = useCallback(
    (searchQuery: string) => {
      if (!issueId) return
      if (searchQuery.trim() === '') {
        setSearchResults(undefined)
        setSearchLoading(false)
        return
      }
      // run query on search
      setSearchLoading(true)
      fetchQuery<RepositoryPickerPossibleTransferRepositoriesQuery>(relayEnvironment, PossibleTransferRepositories, {
        searchQuery,
        issueId,
      }).subscribe({
        next: (data: RepositoryPickerPossibleTransferRepositoriesQuery$data) => {
          if (data !== null) {
            const fetchedRepos = (data.node?.possibleTransferRepositoriesForViewer?.edges || []).flatMap(node =>
              // eslint-disable-next-line no-restricted-syntax
              node?.node ? [readInlineData<RepositoryPickerRepository$key>(RepositoryFragment, node.node)] : [],
            )

            const currentFilter = filterRef.current
            // Only update the search results if the search query is the same as the current filter.
            // We don't need to render each search result if the user has already changed the search query.
            if (searchQuery.trim() === currentFilter.trim()) {
              setSearchResults(fetchedRepos)
              setSearchLoading(false)
            }
          }
        },
        error: () => {
          setSearchLoading(false)
        },
      })
    },
    [relayEnvironment, issueId],
  )

  const fetchRepos = useCallback(
    (searchQuery: string, orgs: string[]) => {
      if (searchQuery.trim() === '') {
        setSearchResults(undefined)
        setSearchLoading(false)
        return
      }
      // run query on search
      setSearchLoading(true)
      fetchQuery<RepositoryPickerSearchRepositoriesQuery>(relayEnvironment, SearchRepositories, {
        searchQuery: getRepositorySearchQuery(searchQuery, organization, exclude, includeForks, currentRepoVisibility),
      }).subscribe({
        next: (data: RepositoryPickerSearchRepositoriesQuery$data) => {
          if (data !== null) {
            let fetchedRepos = (data.search.nodes || []).flatMap(node =>
              // eslint-disable-next-line no-restricted-syntax
              node ? [readInlineData<RepositoryPickerRepository$key>(RepositoryFragment, node)] : [],
            )

            if (hasIssuesEnabled) {
              fetchedRepos = fetchedRepos.filter(repo => repo.hasIssuesEnabled === hasIssuesEnabled)
            }

            let sortedNextSearchResults = fetchedRepos.sort((a, b) => {
              if (orgs.includes(a.owner.login) && !orgs.includes(b.owner.login)) {
                return -1
              } else if (!orgs.includes(a.owner.login) && orgs.includes(b.owner.login)) {
                return 1
              } else {
                return a.owner.login.localeCompare(b.owner.login)
              }
            })

            if (ignoredRepositories) {
              const ignoredSet = new Set(ignoredRepositories)
              sortedNextSearchResults = sortedNextSearchResults.filter(repo => !ignoredSet.has(repo.nameWithOwner))
            }
            if (repositoryFilter) {
              sortedNextSearchResults = sortedNextSearchResults.filter(repositoryFilter)
            }
            const currentFilter = filterRef.current
            // Only update the search results if the search query is the same as the current filter.
            // We don't need to render each search result if the user has already changed the search query.
            if (searchQuery.trim() === currentFilter.trim()) {
              setSearchResults(sortedNextSearchResults)
              setSearchLoading(false)
            }
          }
        },
        error: () => {
          setSearchLoading(false)
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: ERRORS.couldNotSearchRepositories,
          })
        },
      })
    },
    [
      relayEnvironment,
      organization,
      exclude,
      includeForks,
      hasIssuesEnabled,
      ignoredRepositories,
      repositoryFilter,
      addToast,
      currentRepoVisibility,
    ],
  )

  const debounceFetchRepo = useDebounce((nextValue: string) => {
    // If we have an issueId, the user is transferring the issue to a new repo, so we should fetch the possible transfer repos
    if (issueId) {
      fetchPossibleTransferRepos(nextValue)
    } else {
      fetchRepos(nextValue, knownOrgs)
    }
  }, VALUES.pickerDebounceTime)

  const getItemKey = useCallback((o: Repository) => o.id, [])

  const repositoryPickerRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    if (focusRepositoryPicker) repositoryPickerRef.current?.focus()
  }, [repositoryPickerRef, focusRepositoryPicker])

  const renderAnchor = useCallback(
    ({...anchorProps}: React.HTMLAttributes<HTMLElement>) => {
      if (anchorElement) {
        return anchorElement(anchorProps)
      }

      const repositoryValue = initialRepository
        ? repoNameOnly
          ? initialRepository.name
          : initialRepository.nameWithOwner
        : 'No repository selected'

      const label = initialRepository ? `Selected repository: ${repositoryValue}` : LABELS.selectRepository

      return (
        <Button
          leadingVisual={RepoIcon}
          trailingVisual={TriangleDownIcon}
          aria-label={label}
          aria-labelledby={ariaLabelledBy}
          aria-describedby={ariaDescribedBy}
          {...anchorProps}
          disabled={readonly}
          ref={repositoryPickerRef}
        >
          {initialRepository ? (
            <span>
              {repoNameOnly ? initialRepository.name : `${initialRepository.owner.login}/${initialRepository.name}`}
            </span>
          ) : (
            LABELS.selectRepository
          )}
        </Button>
      )
    },
    [anchorElement, ariaDescribedBy, ariaLabelledBy, initialRepository, readonly, repoNameOnly],
  )

  const convertToItemProps = useCallback(
    (repo: Repository): ExtendedItemProps<Repository> => ({
      // this is a hack to make sure that we are using the prop
      id: `${repo.id}_${repo.databaseId}_${repo.slashCommandsEnabled}`,
      children: <span>{repoNameOnly ? repo.name : `${repo.owner.login}/${repo.name}`}</span>,
      source: repo,
      leadingVisual: () => (repo.isPrivate ? <LockIcon size={12} /> : <RepoIcon size={12} />),
      trailingVisual: renderTrailingVisual?.(repo.id),
      sx: {wordBreak: 'break-word'},
    }),
    [renderTrailingVisual, repoNameOnly],
  )

  const data = useFragment(TopRepositoriesFragment, topRepositoriesData)

  const fetchedRepos = useMemo(() => {
    let nodes = (data?.topRepositories.edges || []).flatMap(a =>
      // eslint-disable-next-line no-restricted-syntax
      a?.node ? [readInlineData<RepositoryPickerRepository$key>(RepositoryFragment, a.node)] : [],
    )

    if (initiallySelectedRepo) {
      if (!nodes.find(node => node.id === initiallySelectedRepo.id)) {
        nodes = [initiallySelectedRepo, ...nodes]
      }
    }

    if (initialRepository) {
      if (!nodes.find(node => node.id === initialRepository.id)) {
        nodes = [initialRepository, ...nodes]
      }
    }

    if (organization) {
      nodes = nodes.filter(repo => repo.owner.login === organization)
    }

    if (exclude) {
      nodes = nodes.filter(repo => repo.nameWithOwner !== exclude)
    }

    if (ignoredRepositories) {
      const ignoredSet = new Set(ignoredRepositories)
      nodes = nodes.filter(repo => !ignoredSet.has(repo.nameWithOwner))
    }

    return nodes.slice(0, 10)
  }, [exclude, initiallySelectedRepo, initialRepository, organization, ignoredRepositories, data])

  const knownOrgs = useMemo(() => [...new Set(fetchedRepos.map(repo => repo.owner.login))], [fetchedRepos])

  const items = useMemo(() => {
    if (searchResults) return searchResults
    const filteredItems = fetchedRepos.filter(repo => !repo.isArchived)
    if (repositoryFilter) {
      return filteredItems.filter(repositoryFilter)
    }
    return filteredItems
  }, [fetchedRepos, repositoryFilter, searchResults])

  useEffect(() => {
    // automatically select the first repo
    if (!initialRepository && items.length > 0 && !preventDefault) {
      onSelect(items[0])
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const filterItems = useCallback(
    (value: string) => {
      if (readonly) return
      const trimmedValue = value.trim()
      // Only run search if the value has changed
      if (filter === trimmedValue) return
      debounceFetchRepo(trimmedValue)
      setFilter(trimmedValue)
      filterRef.current = trimmedValue
    },
    [readonly, filter, debounceFetchRepo],
  )

  const showNoMatchMessage = useMemo(() => items.length === 0, [items.length])
  const message = useMemo<SelectPanelProps['message'] | undefined>(
    () =>
      showNoMatchMessage
        ? {
            title: customNoResultsTitle ?? 'No repositories match',
            body: customNoResultsItem ?? 'Try searching with a different query for results.',
            variant: 'empty',
          }
        : undefined,
    [showNoMatchMessage, customNoResultsTitle, customNoResultsItem],
  )

  return (
    <Box sx={{display: 'flex', flexDirection: 'row', flexWrap: 'wrap', gap: 1}}>
      <ItemPicker
        items={items}
        initialSelectedItems={initialRepository ? [initialRepository] : []}
        filterItems={filterItems}
        getItemKey={getItemKey}
        convertToItemProps={convertToItemProps}
        placeholderText={LABELS.selectRepository}
        selectionVariant="single"
        onSelectionChange={([firstRepo]) => {
          return onSelect(firstRepo)
        }}
        loading={searchLoading}
        renderAnchor={renderAnchor}
        selectPanelRef={repositoryPickerRef}
        enforceAtleastOneSelected={enforceAtleastOneSelected}
        resultListAriaLabel={'Repository results'}
        height={'large'}
        width={'medium'}
        title={title}
        subtitle={subtitle}
        preventClose={preventClose}
        triggerOpen={triggerOpen}
        onOpen={onOpen}
        onClose={onClose}
        pickerId={pickerId}
        improvedNoMatchAccessibility={showNoMatchMessage}
        noMatchMessage={message}
        responsiveOnNarrow={responsiveOnNarrow}
        portalContainerName={portalContainerName}
      />
    </Box>
  )
}
