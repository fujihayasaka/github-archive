/* eslint eslint-comments/no-use: off */
/* eslint-disable relay/unused-fields */
import {useKeyPress} from '@github-ui/use-key-press'
import {TableIcon} from '@primer/octicons-react'
import {SelectPanel, type SelectPanelProps} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import type React from 'react'
import {useCallback, useMemo, useState, useEffect, type HTMLAttributes, type RefAttributes, useRef} from 'react'
import {readInlineData, graphql, useRelayEnvironment, fetchQuery} from 'react-relay'

import {ERRORS} from '../constants/errors'
import {LABELS} from '../constants/labels'
import {useItemPickersContext} from '../contexts/ItemPickersContext'
import type {
  ProjectPickerProject$data as Project,
  ProjectPickerProject$key,
} from './__generated__/ProjectPickerProject.graphql'
import type {ProjectPickerQuery, ProjectPickerQuery$data} from './__generated__/ProjectPickerQuery.graphql'
import {type ItemGroup, noMatchesItem, noResultsItem} from '../shared'
import {SharedPicker} from './SharedPicker'
import {commitAddIssuesToProjectsBulkMutation} from '../mutations/add-issues-to-projects-bulk-mutation'
import type {addIssuesToProjectsBulkMutation$data} from '../mutations/__generated__/addIssuesToProjectsBulkMutation.graphql'
import {commitAddIssuesToProjectsBulkByQueryMutation} from '../mutations/add-issues-to-projects-bulk-by-query-mutation'
import type {addIssuesToProjectsBulkByQueryMutation$data} from '../mutations/__generated__/addIssuesToProjectsBulkByQueryMutation.graphql'
import {getAdjustedOverlayProps, type SharedBulkActionsItemPickerProps} from './ItemPicker'
import {useItemPickerErrorFallback} from '../hooks/useItemPickerErrorFallback'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useDebounce} from '@github-ui/use-debounce'
import type {Subscription} from 'relay-runtime'

import {IS_SERVER} from '@github-ui/ssr-utils'
import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import {VALUES} from '../constants/values'
import {IDS} from '../constants/ids'
import {SELECTORS} from '../constants/selectors'
import {GlobalCommands} from '@github-ui/ui-commands'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {ProjectItemsLimitReachedDialog} from './ProjectItemsLimitReachedDialog'

const recentGroup: ItemGroup = {groupId: 'recent', header: {title: 'Recent', variant: 'filled'}}
const repoGroup: ItemGroup = {groupId: 'repository', header: {title: 'Repository', variant: 'filled'}}
const orgGroup: ItemGroup = {groupId: 'organization', header: {title: 'Organization', variant: 'filled'}}
const selectedGroup: ItemGroup = {groupId: 'selected'}

export const ProjectPickerProjectFragment = graphql`
  fragment ProjectPickerProject on ProjectV2 @inline {
    id
    title
    closed
    number
    url
    viewerCanUpdate
    hasReachedItemsLimit
    __typename
  }
`

export const ProjectPickerGraphqlQuery = graphql`
  query ProjectPickerQuery($owner: String!, $repo: String!, $query: String) {
    repository(owner: $owner, name: $repo) {
      projectsV2(first: 5, query: $query, orderBy: {field: RELEVANCE, direction: DESC}, useFullTermQuery: true) {
        nodes {
          ...ProjectPickerProject
        }
      }
      recentProjects(first: 5) {
        edges {
          node {
            ...ProjectPickerProject
          }
        }
      }
      owner {
        ... on Organization {
          projectsV2(first: 5, orderBy: {field: RELEVANCE, direction: DESC}, query: $query, useFullTermQuery: true) {
            edges {
              node {
                ...ProjectPickerProject
              }
            }
          }
          recentProjects(first: 5) {
            edges {
              node {
                ...ProjectPickerProject
              }
            }
          }
        }
        ... on User {
          projectsV2(first: 5, orderBy: {field: RELEVANCE, direction: DESC}, query: $query, useFullTermQuery: true) {
            edges {
              node {
                ...ProjectPickerProject
              }
            }
          }
          recentProjects(first: 5) {
            edges {
              node {
                ...ProjectPickerProject
              }
            }
          }
        }
      }
    }
  }
`

type AnchoredOverlayAnchorProps = HTMLAttributes<HTMLElement> & RefAttributes<HTMLButtonElement>

export type ProjectPickerProps = {
  pickerId: string
  readonly?: boolean
  selectedProjects: Project[]
  firstSelectedProjectTitle?: string
  onSave: (projects: Project[]) => void
  anchorElement: (props: AnchoredOverlayAnchorProps) => JSX.Element
  insidePortal?: boolean
  /**
   * Whether to render the project picker as a nested select panel (true) versus a standalone select
   * panel (false; default).
   */
  nested?: boolean
  owner: string
  repo: string
  triggerOpen?: boolean
  title?: string
  getSelectedProjects?: (projects: Project[]) => Project[]
}

type SelectPanelWrapperProps = ProjectPickerProps & {
  projectsData: ProjectPickerQuery$data | null
  isLoading?: boolean
}

type BulkProjectPickerProps = Omit<ProjectPickerProps, 'id' | 'onSave'> &
  Omit<SharedBulkActionsItemPickerProps, 'issuesToActOn'> & {
    issueIds: string[]
  }

export const BulkProjectPicker: React.FC<BulkProjectPickerProps> = ({
  pickerId,
  useQueryForAction,
  repositoryId,
  query,
  issueIds,
  readonly,
  selectedProjects,
  firstSelectedProjectTitle,
  insidePortal,
  anchorElement,
  onCompleted,
  onError,
  nested = false,
  owner,
  repo,
  triggerOpen = false,
}) => {
  const environment = useRelayEnvironment()

  const onSave = useCallback(
    (newSelectedProjects: Project[]) => {
      const projectsToAdd = newSelectedProjects.filter(a => !selectedProjects.some(aa => aa.id === a.id))
      const projectsToRemove = selectedProjects.filter(a => !newSelectedProjects.some(aa => aa.id === a.id))
      if (!projectsToAdd.length && !projectsToRemove.length) {
        return
      }
      if (useQueryForAction && repositoryId && query) {
        commitAddIssuesToProjectsBulkByQueryMutation({
          environment,
          input: {
            repositoryId,
            query,
            addToProjectV2Ids: projectsToAdd.map(l => l.id),
            removeFromProjectV2Ids: projectsToRemove.map(l => l.id),
          },
          onCompleted: ({updateIssuesBulkByQuery}: addIssuesToProjectsBulkByQueryMutation$data) => {
            onCompleted?.(updateIssuesBulkByQuery?.jobId || undefined)
          },
        })
      } else {
        commitAddIssuesToProjectsBulkMutation({
          environment,
          input: {
            ids: [...issueIds],
            addToProjectV2Ids: projectsToAdd.map(l => l.id),
            removeFromProjectV2Ids: projectsToRemove.map(l => l.id),
          },
          onCompleted: ({updateIssuesBulk}: addIssuesToProjectsBulkMutation$data) => {
            onCompleted?.(updateIssuesBulk?.jobId || undefined)
          },
          onError: (error: Error) => {
            onError?.(error)
          },
        })
      }
    },
    [environment, issueIds, onCompleted, onError, query, repositoryId, useQueryForAction, selectedProjects],
  )

  return ProjectPicker({
    pickerId, // Should be issue specific, if loaded for a specific issue :)
    readonly,
    selectedProjects: [...selectedProjects], // Clone so we keep the initial state
    firstSelectedProjectTitle,
    insidePortal,
    onSave,
    anchorElement,
    nested,
    owner,
    repo,
    triggerOpen,
  })
}

export function ProjectPicker({anchorElement, triggerOpen, ...rest}: ProjectPickerProps) {
  const [wasTriggered, setWasTriggered] = useState(triggerOpen)
  const handleGlobalCommand = useCallback(() => {
    if (!wasTriggered) {
      setWasTriggered(true)
    }
  }, [wasTriggered])

  if (!wasTriggered) {
    return (
      <>
        <GlobalCommands commands={{'item-pickers:open-projects': handleGlobalCommand}} />
        {anchorElement({
          onClick: () => {
            setWasTriggered(true)
          },
          onKeyPress: (event: React.KeyboardEvent<HTMLLIElement>) => {
            // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
            if (event.key === 'Enter' || event.key === ' ') {
              event.preventDefault()
              setWasTriggered(true)
            }
          },
        })}
      </>
    )
  }

  return (
    <ItemPickerFetcher
      triggerOpen
      anchorElement={props => anchorElement(props)}
      {...rest}
      pickerId="list-header-projects-picker"
    />
  )
}

function ItemPickerFetcher({repo, owner, ...rest}: ProjectPickerProps) {
  const environment = useRelayEnvironment()
  const [isLoading, setIsLoading] = useState(true)
  const [fetchKey, setFetchKey] = useState(0)
  const [isError, setIsError] = useState(false)
  const [data, setData] = useState<ProjectPickerQuery$data | null>(null)

  useEffect(() => {
    if (IS_SERVER) return

    clientSideRelayFetchQueryRetained<ProjectPickerQuery>({
      environment,
      query: ProjectPickerGraphqlQuery,
      variables: {owner, repo},
    }).subscribe({
      next: internalData => {
        setData(internalData)
        setIsLoading(false)
        setIsError(false)
      },
      error: () => {
        setIsError(true)
      },
    })
  }, [environment, fetchKey, owner, repo])

  const {createFallbackComponent} = useItemPickerErrorFallback({
    errorMessage: 'Cannot edit projects right now',
    anchorElement: rest.anchorElement,
    open: true,
  })

  if (isError) {
    return createFallbackComponent(() => setFetchKey(fetchKey + 1))
  }

  return <SelectPanelWrapper projectsData={data} owner={owner} repo={repo} isLoading={isLoading} {...rest} />
}

function SelectPanelWrapper({
  pickerId,
  selectedProjects: initialSelected,
  projectsData: initialProjectsData,
  onSave,
  anchorElement,
  insidePortal,
  owner,
  repo,
  isLoading = false,
  triggerOpen = false,
  readonly,
  title,
  getSelectedProjects,
}: SelectPanelWrapperProps) {
  const [projectsData, setProjectsData] = useState<ProjectPickerQuery$data | null>(initialProjectsData)
  const [inFlightSubscription, setInFlightSubscription] = useState<Subscription | null>(null)
  const [searchLoading, setSearchLoading] = useState<boolean>(false)
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const relayEnvironment = useRelayEnvironment()
  const {addToast} = useToastContext()

  const [filter, setFilter] = useState('')

  const fetchSearchData = useCallback(
    (searchQuery: string) => {
      setSearchLoading(true)
      const subscription = fetchQuery<ProjectPickerQuery>(relayEnvironment, ProjectPickerGraphqlQuery, {
        repo,
        owner,
        query: searchQuery,
      }).subscribe({
        next: (data: ProjectPickerQuery$data) => {
          if (data !== null) {
            setProjectsData(data)
          }
          setSearchLoading(false)
        },
        error: () => {
          setSearchLoading(false)
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: ERRORS.couldNotSearchProjects,
          })
        },
      })
      setInFlightSubscription(subscription)
    },
    // Remove dependency on `addToast` to prevent re-renders and re-trigger the fetching
    // when an error is thrown.
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [owner, relayEnvironment, repo],
  )

  const debounceFetchSearchData = useDebounce(
    (nextValue: string) => fetchSearchData(nextValue),
    VALUES.pickerDebounceTime,
  )

  useEffect(() => {
    if (filter.length === 0) {
      setProjectsData(initialProjectsData)
    } else {
      debounceFetchSearchData(filter)
    }
    inFlightSubscription?.unsubscribe()
    return () => {
      setSearchLoading(false)
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debounceFetchSearchData, filter, initialProjectsData])

  const recentProjects = useMemo(
    () =>
      (projectsData?.repository?.owner?.recentProjects?.edges || []).flatMap(a =>
        a?.node
          ? // eslint-disable-next-line no-restricted-syntax
            [readInlineData<ProjectPickerProject$key>(ProjectPickerProjectFragment, a.node)].filter(
              item => item.closed === false,
            )
          : [],
      ),
    [projectsData],
  )

  const repositoryProjects = useMemo(
    () =>
      (projectsData?.repository?.projectsV2?.nodes || []).flatMap(a =>
        a
          ? // eslint-disable-next-line no-restricted-syntax
            [readInlineData<ProjectPickerProject$key>(ProjectPickerProjectFragment, a)].filter(
              item => item.closed === false,
            )
          : [],
      ),
    [projectsData],
  )

  const organizationProjects = useMemo(
    () =>
      (projectsData?.repository?.owner?.projectsV2?.edges || []).flatMap(a =>
        a?.node
          ? // eslint-disable-next-line no-restricted-syntax
            [readInlineData<ProjectPickerProject$key>(ProjectPickerProjectFragment, a.node)].filter(
              item => item.closed === false,
            )
          : [],
      ),
    [projectsData],
  )

  //
  // Presentation logic
  //

  const initialSelectedProjects = useMemo(
    () =>
      getSelectedProjects
        ? getSelectedProjects([...recentProjects, ...repositoryProjects, ...organizationProjects])
        : initialSelected,
    [getSelectedProjects, initialSelected, organizationProjects, recentProjects, repositoryProjects],
  )

  // Array of Project IDs
  const [selected, setSelected] = useState<string[]>(() => initialSelectedProjects.map(p => p.id))
  // Reset the state for selected projects when the issueId changes
  useEffect(() => {
    setSelected(initialSelectedProjects.map(p => p.id))
  }, [initialSelectedProjects, pickerId])

  /// Convert a Project to an ItemInput object that SelectPanel can render
  const generateItemProps: {(groupId: string, p: Project): ItemInput} = useCallback(
    (groupId, p) => {
      const {title: text, id} = p

      // To prevent at-limit items being removed from the project when opening picker once the projects reached the limit
      const variant =
        p.hasReachedItemsLimit && !initialSelectedProjects.some(proj => proj.id === id)
          ? ('danger' as const)
          : ('default' as const)

      const descriptionVariant = p.hasReachedItemsLimit ? ('block' as const) : ('inline' as const)

      const item = {
        text,
        description: p.hasReachedItemsLimit ? `${LABELS.projectItemsLimitReached}` : undefined,
        descriptionVariant,
        id,
        groupId,
        selected: selected.includes(id),
        disabled: !(readonly || p.viewerCanUpdate),
        leadingVisual: TableIcon,
        variant,
        sx: {wordBreak: 'break-word'},
      }

      return item
    },
    [initialSelectedProjects, selected, readonly],
  )

  /// Set of all projects in the picker
  const allProjects: Record<string, Project[]> = useMemo(() => {
    return {
      selected: initialSelectedProjects,
      recent: recentProjects.filter(
        p =>
          !initialSelectedProjects
            .map(function (pr) {
              return pr.id
            })
            .includes(p.id),
      ),
      repository: repositoryProjects.filter(
        p =>
          !initialSelectedProjects
            .map(function (pr) {
              return pr.id
            })
            .includes(p.id),
      ),
      organization: organizationProjects.filter(
        p =>
          !initialSelectedProjects
            .map(function (pr) {
              return pr.id
            })
            .includes(p.id),
      ),
    }
  }, [initialSelectedProjects, recentProjects, repositoryProjects, organizationProjects])

  const projectsToSelect = useMemo(
    () => Object.keys(allProjects).flatMap(pKey => allProjects[pKey]!.map(p => generateItemProps(pKey, p))),
    [allProjects, generateItemProps],
  )

  /// Subset of projects that have been selected
  const selectedProjects = useMemo(
    () => projectsToSelect.filter(p => p.id && selected.includes(p.id.toString())),
    [selected, projectsToSelect],
  )

  /// Optional search by filtering project title
  const filteredProjects = useMemo(() => {
    // We have nothing to filter
    if (projectsToSelect.length < 1) return [noResultsItem]

    // We have nothing to filter by
    if (filter === '') {
      return projectsToSelect
    }

    const filtered = projectsToSelect.filter(
      item => (item.text || '').toLowerCase().indexOf(filter.trim().toLowerCase()) >= 0,
    )

    // We have no filter matches
    if (filtered.length < 1) return [noMatchesItem]
    return filtered
  }, [filter, projectsToSelect])

  /// Groups to render
  const groups = useMemo(
    () =>
      !filteredProjects.includes(noMatchesItem) && !filteredProjects.includes(noResultsItem)
        ? // We have results, so we can render groups
          [
            initialSelectedProjects.length > 0 ? selectedGroup : null,
            recentProjects.length > 0 ? recentGroup : null,
            repositoryProjects.length > 0 ? repoGroup : null,
            organizationProjects.length > 0 ? orgGroup : null,
          ].filter(group => group !== null)
        : // We have no results, so we can't render groups
          [],
    [
      filteredProjects,
      initialSelectedProjects.length,
      recentProjects.length,
      repositoryProjects.length,
      organizationProjects.length,
    ],
  )

  const handleSelectionChange = useCallback(
    (selection: ItemInput[]) => {
      // Find out if the selection now excludes a previously selected item, i.e. the diff
      const diff = selectedProjects.filter(p => !selection.includes(p)).map(p => p.id)
      let projectIds: Array<string | number> = selected

      // Handle selected projects
      const selectedIds = selection
        // Filter out items that don't have IDs
        .filter(item => item.id !== undefined)
        // Pull out the IDs and cast them
        .map(item => item.id) as Array<string | number>
      projectIds = [...projectIds, ...selectedIds]

      // Handle removed projects
      if (diff.length > 0) {
        projectIds = projectIds.filter(p => !diff.includes(p))
      }

      const projectIdsSet = new Set(projectIds.map(id => id.toString()))
      setSelected([...projectIdsSet])
    },
    [setSelected, selectedProjects, selected],
  )

  const {updateOpenState} = useItemPickersContext()
  const [isOpen, setOpen] = useState(triggerOpen)

  const onSpaceKeyPress = (event: KeyboardEvent) => {
    if (isOpen) {
      const activeOption = document.querySelector(SELECTORS.activePickerOption(IDS.itemPickerRootId))

      if (activeOption) {
        const activeDataId = activeOption.getAttribute('data-id')
        const item = [...filteredProjects.values()].find(i => i.id === activeDataId)

        if (item && item.id) {
          event.preventDefault()
          event.stopPropagation()

          setSelected(prevState => {
            const newState = [...prevState]
            const index = newState.indexOf(item.id!.toString())
            if (index > -1) {
              newState.splice(index, 1)
            } else {
              newState.push(item.id!.toString())
            }
            return newState
          })
        }
      }
    }
  }

  useKeyPress([' '], onSpaceKeyPress, {
    triggerWhenInputElementHasFocus: true,
    triggerWhenPortalIsActive: true,
  })

  const blurOnCloseEnabled = isFeatureEnabled('issues_react_blur_item_picker_on_close')

  const onOpenChange = useCallback(
    (open: boolean) => {
      // Fix for an issue in safari where the issue would scroll down all the way
      // when the item picker is closed with escape
      if (blurOnCloseEnabled && !open && document.activeElement instanceof HTMLElement) {
        // eslint-disable-next-line github/no-blur
        document.activeElement?.blur()
      }
      setOpen(open)
      updateOpenState(pickerId, open)
      if (!open) {
        setFilter('')

        // If any of the selected projects have the danger variant (meaning that the items limit is reached), open the dialog
        // We use danger and not hasReachedItemsLimit because the deprecated ItemInput type does not have hasReachedItemsLimit prop (node_modules/@primer/react/lib-esm/deprecated/ActionList/List.d.ts)
        const dangerItems = selectedProjects.filter(item => item.variant === 'danger')
        if (dangerItems.length > 0) {
          setIsDialogOpen(true)
        }

        // To prevent them from being checked on reopen of the picker (without reloading the page)
        const validSelected = selectedProjects
          .filter(item => item.variant !== 'danger')
          .map(p => p.id)
          .filter((id): id is string => id !== undefined)

        setSelected(validSelected)

        const uniqueProjects: Project[] = validSelected
          .flatMap(
            id =>
              Object.keys(allProjects)
                .flatMap(pKey => allProjects[pKey]!)
                .find(p => p.id === id) || [],
          )
          .filter((value, index, array) => {
            return array.findIndex(current => current.id === value.id) === index
          })
        onSave(uniqueProjects.filter(p => p !== undefined))
      }
    },
    [blurOnCloseEnabled, updateOpenState, pickerId, selectedProjects, onSave, allProjects],
  )

  const handleGlobalCommand = useCallback(() => {
    if (isOpen) return

    onOpenChange(true)
  }, [isOpen, onOpenChange])

  const buttonRef = useRef<HTMLButtonElement>(null)
  const regularHeight = filteredProjects.length <= 2 ? 'auto' : 'large'
  const adjustedOverlayProps = getAdjustedOverlayProps(insidePortal, buttonRef, regularHeight)

  const selectPanelProps = useMemo<SelectPanelProps>(() => {
    const props: SelectPanelProps = {
      renderAnchor: anchorProps => anchorElement(anchorProps),
      anchorRef: buttonRef,
      placeholderText: LABELS.filterProjects,
      items: filteredProjects,
      selected: selectedProjects,
      open: isOpen,
      onOpenChange,
      onSelectedChange: handleSelectionChange,
      filterValue: filter,
      onFilterChange: setFilter,
      showItemDividers: true,
      overlayProps: {
        width: 'medium',
        ...adjustedOverlayProps,
      } as const,
      loading: isLoading || searchLoading,
      title: title ?? LABELS.selectProjects,
    }

    if (groups?.length > 0 && filteredProjects.length > 0) {
      props.groupMetadata = groups
    }

    return props
  }, [
    adjustedOverlayProps,
    anchorElement,
    filter,
    filteredProjects,
    groups,
    handleSelectionChange,
    isLoading,
    isOpen,
    onOpenChange,
    searchLoading,
    selectedProjects,
    title,
  ])

  const handleDialogClose = useCallback(() => {
    setIsDialogOpen(false)
  }, [setIsDialogOpen])

  return (
    <>
      <GlobalCommands commands={{'item-pickers:open-projects': handleGlobalCommand}} />
      <SelectPanel
        aria-label="Project results"
        data-id={IDS.itemPickerRootId}
        data-testid={IDS.itemPickerTestId}
        {...selectPanelProps}
      />
      {isDialogOpen && <ProjectItemsLimitReachedDialog onClose={handleDialogClose} returnFocusRef={buttonRef} />}
    </>
  )
}

export function DefaultProjectPickerAnchor({
  firstSelectedProjectTitle,
  readonly,
  nested,
  anchorProps,
}: Pick<ProjectPickerProps, 'firstSelectedProjectTitle' | 'readonly' | 'nested'> & {
  anchorProps?: React.HTMLAttributes<HTMLElement> | undefined
}) {
  return (
    <SharedPicker
      anchorText={LABELS.noProjects}
      sharedPickerMainValue={firstSelectedProjectTitle}
      anchorProps={readonly ? undefined : anchorProps}
      ariaLabel={LABELS.selectProjects}
      readonly={readonly}
      nested={nested}
      leadingIcon={TableIcon}
      hotKey={undefined}
    />
  )
}
