import {useCallback, useEffect, useRef, useState} from 'react'
import {Button} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {type ExtendedItemProps, ItemPicker} from '@github-ui/item-picker/ItemPicker'
import {LABELS} from '@github-ui/item-picker/Labels'
import {Banner} from '@primer/react/experimental'
import {GitBranchIcon, GitPullRequestIcon, TriangleDownIcon} from '@primer/octicons-react'
import {useDebounce} from '@github-ui/use-debounce'
import {VALUES} from '@github-ui/item-picker/Values'
import {useQuery, keepPreviousData} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {PullRequestStateIcons} from '@github-ui/item-picker/Icons'
import type {ItemGroup} from '@github-ui/item-picker/shared'
import type {BranchPickerData, PullRequestPickerData, SearchResult, SearchResults} from '../types'
import styles from './TSQPullRequestAndBranchPicker.module.css'

type PullRequestAndBranchPickerSharedProps = {
  onSelectionChange: (selected: SearchResult[]) => void
  shortcutsEnabled: boolean
  anchorElement?: (props: React.HTMLAttributes<HTMLElement>) => JSX.Element
  subtitle?: string | React.ReactElement
  title?: string | React.ReactElement
  triggerOpen?: boolean
  onOpen?: () => void
  onClose?: () => void
  preventClose?: boolean
  loading?: boolean
  linkableItemsSearchPath: string
}

export type PullRequestAndBranchPickerProps = PullRequestAndBranchPickerSharedProps & {
  initialSelectedPullRequests: PullRequestPickerData[]
  initialSelectedBranches: BranchPickerData[]
  preventClose?: boolean
  mutationError: Error | null
}

type PullRequestPickerInternalProps = Omit<PullRequestAndBranchPickerSharedProps, 'linkableItemsSearchPath'> & {
  initialSelectedBranches: BranchPickerData[]
  initialSelectedPullRequests: PullRequestPickerData[]
  foundBranches: BranchPickerData[]
  foundPullRequests: PullRequestPickerData[]
  onFilter: (value: string) => void
  searchError: Error | null
  mutationError: Error | null
}

export type PullRequestPickerBaseProps = Omit<
  PullRequestPickerInternalProps,
  'pullRequestItemsKey' | 'branchItemsKey' | 'foundBranches' | 'foundPullRequests'
> & {
  branchItems: BranchPickerData[]
  pullRequestItems: PullRequestPickerData[]
}

const selectedGroup: ItemGroup = {groupId: 'selected'}
const suggestionsGroup: ItemGroup = {groupId: 'suggestions', header: {title: 'Suggestions', variant: 'filled'}}

export const LazyPullRequestAndBranchPicker = ({
  initialSelectedBranches,
  initialSelectedPullRequests,
  loading,
  linkableItemsSearchPath,
  ...rest
}: PullRequestAndBranchPickerProps) => {
  const [isOpened, setIsOpened] = useState(false)
  const [filter, setFilter] = useState('')
  const [debouncedFilter, setDebouncedFilter] = useState('')

  function onFilter(value: string) {
    setFilter(value)
  }

  const updateDebouncedFilter = useDebounce((newFilter: string) => {
    setDebouncedFilter(newFilter)
  }, VALUES.pickerDebounceTime)

  useEffect(() => {
    updateDebouncedFilter(filter)
  }, [updateDebouncedFilter, filter])

  const {data, isPending, isRefetching, error} = useQuery<SearchResults>({
    queryKey: ['code-scanning-development-section', linkableItemsSearchPath, debouncedFilter],
    queryFn: async () => {
      const url = new URL(linkableItemsSearchPath, window.location.origin)
      url.searchParams.set('query', debouncedFilter)
      const response = await verifiedFetchJSON(`${url.pathname}${url.search}`)
      if (!response.ok) {
        throw new Error(`${response.status} on ${response.url}`)
      }
      return response.json()
    },
    // This makes the functional be like an autocomplete widget.
    // For example, you type "a" and it suggests "Anders, Ant, Apple".
    // then, when you type "an", until new results are fetched, it continues to
    // show "Anders, Ant, Apple" (the previous results), even though "Apple" should
    // cease to be suggested.
    // But the alternative to using this technique is causing flicker. After you've keypressed
    // "an", it would remove all suggestions and only show suggestions when it has "Anders, Ant"
    // left to show.
    placeholderData: keepPreviousData,
    // Simply opening the menu means we're going to trigger a "search"
    // even though the user might not have typed in any search string.
    enabled: isOpened,
  })

  return (
    <PullRequestAndBranchPickerInternal
      initialSelectedBranches={initialSelectedBranches}
      initialSelectedPullRequests={initialSelectedPullRequests}
      foundBranches={data ? data.results.filter(find => find.type === 'branch') : []}
      foundPullRequests={data ? data.results.filter(find => find.type === 'pull_request') : []}
      onOpen={() => setIsOpened(true)}
      onClose={() => setIsOpened(false)}
      onFilter={onFilter}
      // The first `loading` is coming from outside the component.
      // The `isPending` is for the first search XHR.
      // The `isRefetching` is for any following search XHR. This is how it
      // work when you use `placeholderData: keepPreviousData` in useQuery.
      loading={loading || isPending || isRefetching}
      searchError={error}
      {...rest}
    />
  )
}

function PullRequestAndBranchPickerInternal({
  initialSelectedBranches,
  initialSelectedPullRequests,
  foundBranches,
  foundPullRequests,
  ...rest
}: PullRequestPickerInternalProps) {
  const pullRequestItems = initialSelectedPullRequests.concat(
    foundPullRequests.filter(item => !initialSelectedPullRequests.some(r => r.number === item.number)),
  )
  const branchItems = initialSelectedBranches.concat(
    foundBranches.filter(item => !initialSelectedBranches.some(r => r.name === item.name)),
  )

  return (
    <PullRequestAndBranchPickerBase
      initialSelectedBranches={initialSelectedBranches}
      initialSelectedPullRequests={initialSelectedPullRequests}
      pullRequestItems={pullRequestItems}
      branchItems={branchItems}
      {...rest}
    />
  )
}

function getItemKey(item: SearchResult) {
  return `${item.type === 'pull_request' ? item.number : item.name}${item.type}`
}

// This is exported for the sake of the Storybook story
export function PullRequestAndBranchPickerBase({
  pullRequestItems,
  branchItems,
  initialSelectedBranches,
  initialSelectedPullRequests,
  loading,
  onFilter,
  anchorElement,
  shortcutsEnabled,
  searchError,
  mutationError,
  ...rest
}: PullRequestPickerBaseProps) {
  const pullRequestPickerRef = useRef<HTMLButtonElement>(null)

  const groups = [selectedGroup]
  if (
    pullRequestItems.length + branchItems.length >
    initialSelectedBranches.length + initialSelectedPullRequests.length
  ) {
    groups.push(suggestionsGroup)
  }

  const convertToItemProps = useCallback(
    (item: SearchResult): ExtendedItemProps<SearchResult> => {
      const isPr = item.type === 'pull_request'
      const displayName = isPr ? item.title : item.name
      const displaySubtitle = isPr ? `#${item.number}` : LABELS.noPullRequest
      const icon = isPr ? getPrIcon(item) : <Octicon icon={GitBranchIcon} size={16} />

      const group =
        (isPr && initialSelectedPullRequests.some(pr => pr.number === item.number)) ||
        (!isPr && initialSelectedBranches.some(br => br.name === item.name))
          ? selectedGroup
          : suggestionsGroup

      return {
        // this is a hack to make sure that we are using the prop
        id: `${item.type === 'pull_request' ? item.number : item.name}`,
        groupId: group.groupId,
        children: (
          <div className={styles.NameDisplay}>
            <span>{displayName}</span>
            <span className={styles.SubTitle}>{displaySubtitle}</span>
          </div>
        ),
        source: item,
        leadingVisual: () => icon,
      }
    },
    [initialSelectedBranches, initialSelectedPullRequests],
  )

  const renderAnchor = useCallback(
    ({...anchorProps}: React.HTMLAttributes<HTMLElement>) => {
      if (anchorElement) {
        return anchorElement(anchorProps)
      }

      const initialSelectedItems = [...initialSelectedPullRequests, ...initialSelectedBranches]
      return (
        <Button
          leadingVisual={GitPullRequestIcon}
          trailingVisual={TriangleDownIcon}
          {...anchorProps}
          aria-labelledby="pr-picker-label"
          ref={pullRequestPickerRef}
        >
          {initialSelectedItems.length > 0
            ? LABELS.getNumberOfSelectedPrsLabel(initialSelectedItems.length)
            : LABELS.selectPr}
        </Button>
      )
    },
    [anchorElement, initialSelectedPullRequests, initialSelectedBranches],
  )

  return (
    <div className={styles.ItemPickerContainer}>
      <ItemPicker<SearchResult>
        loading={loading}
        items={[...pullRequestItems, ...branchItems]}
        initialSelectedItems={[...initialSelectedPullRequests, ...initialSelectedBranches]}
        groups={groups}
        filterItems={onFilter}
        getItemKey={getItemKey}
        convertToItemProps={convertToItemProps}
        placeholderText={LABELS.searchPr}
        selectionVariant="multiple"
        selectPanelRef={pullRequestPickerRef}
        renderAnchor={renderAnchor}
        width="medium"
        resultListAriaLabel="Pull request and branch search results"
        height="large"
        subtitle={
          searchError ? (
            <Banner
              aria-label="Critical"
              title="Search error"
              description="Unable to complete the search for pull requests and branches. Try a moment later."
              variant="critical"
            />
          ) : mutationError ? (
            <Banner
              aria-label="Critical"
              title="Save error"
              description="Unable to save your selection due to server error. Try a moment later."
              variant="critical"
            />
          ) : undefined
        }
        {...rest}
      />
    </div>
  )
}

function getPrIcon({state, merged, draft}: PullRequestPickerData) {
  const prState: keyof typeof PullRequestStateIcons = merged
    ? 'MERGED'
    : draft
      ? 'DRAFT'
      : state === 'OPEN'
        ? 'OPEN'
        : 'CLOSED'
  const {color, icon} = PullRequestStateIcons[prState]
  // The explanation for the eslint disable is that you can't use `<Octicon color={color} ...>`,
  // which works everywhere else, but not within the context of the `leadingVisual` within
  // the `convertToItemProps` callback.
  // Until we've figured this out, let's leave this be `sx` a little longer.
  // eslint-disable-next-line @github-ui/github-monorepo/no-sx
  return <Octicon icon={icon} size={16} sx={{path: {fill: color}}} />
}
