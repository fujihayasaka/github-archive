import {
  Filter,
  type FilterQuery,
  type FilterProvider,
  ValidationMessage,
  FILTER_KEYS,
  SubmitEvent,
} from '@github-ui/filter'
import {
  AssigneeFilterProvider,
  AuthorFilterProvider,
  ClosedFilterProvider,
  CommenterFilterProvider,
  CommentsFilterProvider,
  CreatedFilterProvider,
  InteractionsFilterProvider,
  InvolvesFilterProvider,
  IsFilterProvider,
  LabelFilterProvider,
  MentionsFilterProvider,
  ParentIssueFilterProvider,
  MilestoneFilterProvider,
  ProjectFilterProvider,
  SortFilterProvider,
  StateFilterProvider,
  TeamFilterProvider,
  ReasonFilterProvider,
  RepositoryFilterProvider,
  LinkedFilterProvider,
  UpdatedFilterProvider,
  ArchivedFilterProvider,
  MergedFilterProvider,
  ReactionsFilterProvider,
  DraftFilterProvider,
  ReviewFilterProvider,
  LanguageFilterProvider,
  OrgFilterProvider,
  ReviewRequestedFilterProvider,
  UserFilterProvider,
  TeamReviewRequestedFilterProvider,
  ShaFilterProvider,
  BaseFilterProvider,
  HeadFilterProvider,
  StatusFilterProvider,
  UserReviewRequestedFilterProvider,
  ReviewedByFilterProvider,
  InFilterProvider,
} from '@github-ui/filter/providers'
import {TypeFilterProvider} from '@github-ui/filter/providers/type'

import {HOTKEYS} from '@github-ui/issue-viewer/Hotkeys'

import {noop} from '@github-ui/noop'

import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {ModifierKeys, useKeyPress} from '@github-ui/use-key-press'
import {useUser} from '@github-ui/use-user'
import {Button, FormControl} from '@primer/react'
import {type ReactNode, useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {graphql, useFragment, useRelayEnvironment} from 'react-relay'
import {useLocation, useParams} from 'react-router-dom'

import {
  ASSIGNED_TO_ME_VIEW,
  CUSTOM_VIEW,
  KNOWN_VIEWS,
  REPOSITORY_VIEW,
  DEFAULT_QUERY,
} from '../../constants/view-constants'
import {useHyperlistAnalytics} from '../../hooks/use-hyperlist-analytics'
import type {AppPayload} from '../../types/app-payload'
import {
  isNewIssuePath,
  isCustomViewIssuePathForRepo,
  isCreatedByAppIssuePathForRepo,
  searchUrl,
  removeInvalidFiltersFromQuery,
} from '../../utils/urls'
import {isTypeFilterProvider} from '../../utils/type-predicates'
import type {SearchBarCurrentViewFragment$key} from './__generated__/SearchBarCurrentViewFragment.graphql'
import {BUTTON_LABELS} from '../../constants/buttons'
import {LABELS} from '../../constants/labels'
import {MESSAGES} from '../../constants/messages'
import {useQueryContext, useQueryEditContext} from '../../contexts/QueryContext'
import {useAppNavigate} from '../../hooks/use-app-navigate'
import {commitRemoveTeamViewMutation} from '../../mutations/remove-team-view-mutation'
import {commitRemoveUserViewMutation} from '../../mutations/remove-user-view-mutation'
import {IS_FILTER_PROVIDER_VALUES} from '../../constants/values'
import styles from './SearchBar.module.css'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {SubIssueFilterProvider} from './providers/sub-issue'
import {SearchBarActions} from './SearchBarActions'
import type {SearchBarActionsRepositoryFragment$key} from './__generated__/SearchBarActionsRepositoryFragment.graphql'

type SearchBarProps = {
  currentView: SearchBarCurrentViewFragment$key
  currentRepository: SearchBarActionsRepositoryFragment$key | null
  queryFromCustomView?: string | null
}

const DynamicWrapper = ({editing, children}: {editing: boolean; children: ReactNode}) => {
  return editing ? <FormControl>{children}</FormControl> : <>{children}</>
}

export function SearchBar({currentView, currentRepository, queryFromCustomView}: SearchBarProps) {
  const ref = useRef<HTMLInputElement>(null)

  const {
    setActiveSearchQuery,
    isCustomView,
    setIsEditing,
    isEditing,
    viewTeamId,
    isNewView,
    setIsNewView,
    dirtyViewId,
    setDirtyViewId,
    dirtyViewType,
    setDirtyViewType,
    setCurrentPage,
  } = useQueryContext()

  const [validationMessage, setValidationMessage] = useState<string[]>([])

  const {issue_types, sub_issues} = useFeatureFlags()

  const issues_advanced_search = isFeatureEnabled('issues_advanced_search')
  const issues_advanced_search_has_filter = isFeatureEnabled('issues_advanced_search_has_filter')

  const {search, pathname} = useLocation()

  const urlSearchParams = new URLSearchParams(search)
  const urlQuery = urlSearchParams.get('q')

  const {scoped_repository, current_user_settings} = useAppPayload<AppPayload>()

  const relayEnvironment = useRelayEnvironment()
  const {navigateToView, navigateToUrl} = useAppNavigate()

  // GenericView is a union type between team and user search shortcut
  // Adding this here resulted in possible null values for the returned props
  // It should not be the case
  const {
    id: viewId,
    color: viewColor,
    name: viewName,
    description: viewDescription,
    icon: viewIcon,
    scopingRepository,
    query,
  } = useFragment<SearchBarCurrentViewFragment$key>(
    graphql`
      fragment SearchBarCurrentViewFragment on Shortcutable {
        id
        name
        description
        icon
        color
        query
        scopingRepository {
          name
          owner {
            login
          }
        }
      }
    `,
    currentView,
  )

  const {author, assignee, mentioned} = useParams<{author: string; assignee: string; mentioned: string}>()
  const customViewQuery = `${CUSTOM_VIEW.defaultQuery} ${CUSTOM_VIEW.query({
    author,
    assignee,
    mentioned,
    createdByApp: isCreatedByAppIssuePathForRepo(pathname),
  })}`
  const viewQuery = isCustomViewIssuePathForRepo(pathname) ? customViewQuery : query

  const modifiedQuery = scopingRepository
    ? `repo:${scopingRepository.owner.login}/${scopingRepository.name} ${viewQuery}`
    : `${viewQuery}`

  const {
    dirtyTitle,
    setDirtyTitle,
    dirtyDescription,
    setDirtyDescription,
    commitUserViewEdit,
    commitTeamViewEdit,
    dirtySearchQuery,
    setDirtySearchQuery,
    dirtyViewIcon,
    setDirtyViewIcon,
    dirtyViewColor,
    setDirtyViewColor,
  } = useQueryEditContext()

  const setCurrentQuery = useCallback(
    (currentQuery: string) => {
      setActiveSearchQuery(currentQuery)
      const queryWithTrailingSpace = currentQuery !== '' ? `${currentQuery.trim()} ` : ''
      setDirtySearchQuery(queryWithTrailingSpace)
    },
    [setActiveSearchQuery, setDirtySearchQuery],
  )

  useEffect(() => {
    if (!isNewIssuePath(pathname)) {
      const currentQuery = urlQuery || modifiedQuery || ''
      setCurrentQuery(currentQuery)
    }
  }, [modifiedQuery, setCurrentQuery, urlQuery, pathname])

  const {sendHyperlistAnalyticsEvent} = useHyperlistAnalytics()

  const onSubmit = useCallback(
    (request: FilterQuery, event: SubmitEvent) => {
      let searchQuery = request.raw
      if (event === SubmitEvent.Clear) {
        searchQuery = modifiedQuery
        setCurrentQuery(modifiedQuery)
      }

      let finalQuery = searchQuery ? searchQuery : DEFAULT_QUERY

      const filterConfig = request.config
      // when the filter is using the parser v2 that supports the advanced search grammar,
      // the query is already validated by this point and incompatible with the following sanitization
      if (!filterConfig.groupAndKeywordSupport) {
        finalQuery = removeInvalidFiltersFromQuery(searchQuery)
      }
      sendHyperlistAnalyticsEvent('search.execute', 'FILTER_BAR_INPUT', {new_query: finalQuery})

      const searchViewId = isCustomView(viewId) || scoped_repository ? viewId : undefined
      const url = searchUrl({viewId: searchViewId, query: finalQuery})
      navigateToUrl(url, {preventAutofocus: true})
      setCurrentPage(1)
    },
    [
      isCustomView,
      modifiedQuery,
      navigateToUrl,
      scoped_repository,
      sendHyperlistAnalyticsEvent,
      setCurrentPage,
      setCurrentQuery,
      viewId,
    ],
  )

  const onShortcutKeyPress = useCallback(
    (e: KeyboardEvent) => {
      if (!current_user_settings?.use_single_key_shortcut) {
        return
      }

      if (ref && ref.current) {
        ref.current.focus()
        const queryLength = ref.current.value?.length || 0
        ref.current.setSelectionRange(queryLength, queryLength)
        e.preventDefault()
      }
    },
    [current_user_settings?.use_single_key_shortcut],
  )

  const deleteDirtyView = useCallback(
    (willNavigate: boolean) => {
      if (dirtyViewId === undefined) {
        return
      }

      const payload = {
        environment: relayEnvironment,
        input: {shortcutId: dirtyViewId},
        onError: () => noop,
        onCompleted: () => {
          if (willNavigate) {
            navigateToView({viewId: ASSIGNED_TO_ME_VIEW.id, canEditView: true})
          }
        },
      }

      if (dirtyViewType === 'team') commitRemoveTeamViewMutation(payload)
      else commitRemoveUserViewMutation(payload)
    },
    [dirtyViewId, dirtyViewType, navigateToView, relayEnvironment],
  )

  const onCancel = useCallback(() => {
    setDirtyTitle(viewName)
    setDirtyDescription(viewDescription)
    setDirtySearchQuery(modifiedQuery)
    setDirtyViewIcon(viewIcon)
    setDirtyViewColor(viewColor)
    setIsEditing(false)
    setIsNewView(false)
    setDirtyViewId(undefined)
    setDirtyViewType(undefined)
    deleteDirtyView(true)
  }, [
    setDirtyTitle,
    viewName,
    setDirtyDescription,
    viewDescription,
    setDirtySearchQuery,
    modifiedQuery,
    setDirtyViewIcon,
    viewIcon,
    setDirtyViewColor,
    viewColor,
    setIsEditing,
    setIsNewView,
    setDirtyViewId,
    setDirtyViewType,
    deleteDirtyView,
  ])

  const onInputChange = useCallback(
    (filter: string) => {
      setDirtySearchQuery(filter)
    },
    [setDirtySearchQuery],
  )

  const onValidation = useCallback((messages: string[]) => setValidationMessage(messages), [setValidationMessage])

  const onUpdateViewQuery = useCallback(() => {
    if (ref?.current?.value !== undefined && dirtyTitle.trim() !== '') {
      sendHyperlistAnalyticsEvent('search.save', 'FILTER_BAR_SAVE_BUTTON', {
        new_color: dirtyViewColor,
        new_icon: dirtyViewIcon,
        new_query: dirtySearchQuery,
        new_view_description: dirtyDescription,
        new_view_name: dirtyTitle,
        prev_color: viewColor,
        prev_icon: viewIcon,
        prev_query: modifiedQuery,
        prev_view_description: viewDescription,
        prev_view_name: viewName,
      })
      const args = {
        viewId,
        onSuccess: () => {
          const url = searchUrl({viewId})
          window.history.replaceState(history.state, '', url)
          setIsEditing(false)
        },
        relayEnvironment,
      }

      if (viewTeamId) {
        commitTeamViewEdit(args)
      } else {
        commitUserViewEdit(args)
      }
      setIsNewView(false)
      setDirtyViewId(undefined)
      setDirtyViewType(undefined)
    }
  }, [
    dirtyTitle,
    sendHyperlistAnalyticsEvent,
    dirtyViewColor,
    dirtyViewIcon,
    dirtySearchQuery,
    dirtyDescription,
    viewColor,
    viewIcon,
    modifiedQuery,
    viewDescription,
    viewName,
    viewId,
    relayEnvironment,
    viewTeamId,
    commitTeamViewEdit,
    commitUserViewEdit,
    setIsNewView,
    setDirtyViewId,
    setDirtyViewType,
    setIsEditing,
  ])

  useKeyPress([HOTKEYS.focusSearch], onShortcutKeyPress, {[ModifierKeys.metaKey]: true})
  useKeyPress([HOTKEYS.focusSearch], onShortcutKeyPress, {[ModifierKeys.ctrlKey]: true})

  const {currentUser} = useUser()

  // We can only get into a valid edit state if details are not being shown for a custom view header
  const editingContent = isEditing && isCustomView(viewId)

  useEffect(() => {
    if (!isNewView) {
      if (dirtyViewId !== undefined) {
        deleteDirtyView(false)
      }
      setDirtyViewType(undefined)
      setDirtyViewId(undefined)
    }
  }, [deleteDirtyView, dirtyViewId, editingContent, isNewView, setDirtyViewId, setDirtyViewType])

  const queryFromViewId = isCustomViewIssuePathForRepo(pathname)
    ? customViewQuery
    : KNOWN_VIEWS.find(v => v.id === viewId)?.query

  // In a repo index, we give precendence to the query from the URL over the query from the viewId
  const effectiveQueryFromViewId = useMemo(
    () => (viewId === REPOSITORY_VIEW.id ? urlQuery ?? queryFromViewId : queryFromViewId ?? urlQuery),
    [queryFromViewId, urlQuery, viewId],
  )
  const effectiveQuery = useMemo(() => {
    return dirtySearchQuery ?? effectiveQueryFromViewId ?? queryFromCustomView ?? ''
  }, [dirtySearchQuery, effectiveQueryFromViewId, queryFromCustomView])

  const providerRepositoryScope = scoped_repository ? `${scoped_repository.owner}/${scoped_repository.name}` : undefined

  const providers = useMemo(() => {
    const userFilterParam = {
      showAtMe: !!currentUser,
      currentUserLogin: currentUser?.login,
      currentUserAvatarUrl: currentUser?.avatarUrl,
      repositoryScope: providerRepositoryScope,
    }

    const noNoneValueFilterConfig = {filterTypes: {valueless: false}}

    const hasFilterEnabled = issues_advanced_search && issues_advanced_search_has_filter
    const hasValueFilterConfig = {filterTypes: {hasValue: hasFilterEnabled}}

    const filterProviders: FilterProvider[] = [
      new IsFilterProvider(IS_FILTER_PROVIDER_VALUES, noNoneValueFilterConfig),
      new InFilterProvider(),
      new StateFilterProvider('mixed', noNoneValueFilterConfig),
      new ProjectFilterProvider(hasValueFilterConfig),
      new LabelFilterProvider(hasValueFilterConfig),
      new MilestoneFilterProvider(hasValueFilterConfig),
      new AuthorFilterProvider(userFilterParam, noNoneValueFilterConfig),
      new AssigneeFilterProvider({...userFilterParam, showHasValue: true}, hasValueFilterConfig),
      new ClosedFilterProvider(noNoneValueFilterConfig),
      new CreatedFilterProvider(noNoneValueFilterConfig),
      new UpdatedFilterProvider(noNoneValueFilterConfig),
      new MentionsFilterProvider(userFilterParam, noNoneValueFilterConfig),
      new CommenterFilterProvider(userFilterParam, noNoneValueFilterConfig),
      new InvolvesFilterProvider(userFilterParam, noNoneValueFilterConfig),
      new ReviewRequestedFilterProvider(userFilterParam, noNoneValueFilterConfig),
      new UserFilterProvider(userFilterParam, noNoneValueFilterConfig),
      new UserReviewRequestedFilterProvider(userFilterParam, noNoneValueFilterConfig),
      new ReviewedByFilterProvider(userFilterParam, noNoneValueFilterConfig),
      new CommentsFilterProvider(noNoneValueFilterConfig),
      new InteractionsFilterProvider(noNoneValueFilterConfig),
      new SortFilterProvider(['created', 'updated', 'reactions', 'comments', 'relevance'], noNoneValueFilterConfig),
      new TypeFilterProvider(
        hasValueFilterConfig,
        // legacy support for `type:issue` and `type:pr`
        true,
        relayEnvironment,
        providerRepositoryScope,
        issue_types,
      ),
      new ReasonFilterProvider(noNoneValueFilterConfig),
      new LinkedFilterProvider(['issue', 'pr'], noNoneValueFilterConfig),
      new ArchivedFilterProvider(noNoneValueFilterConfig),
      new MergedFilterProvider(noNoneValueFilterConfig),
      new ReactionsFilterProvider(noNoneValueFilterConfig),
      new DraftFilterProvider(noNoneValueFilterConfig),
      new ReviewFilterProvider(noNoneValueFilterConfig),
      new LanguageFilterProvider(noNoneValueFilterConfig),
      new ShaFilterProvider(noNoneValueFilterConfig),
      new BaseFilterProvider(noNoneValueFilterConfig),
      new HeadFilterProvider(noNoneValueFilterConfig),
      new StatusFilterProvider(noNoneValueFilterConfig),
      new TeamFilterProvider(providerRepositoryScope, noNoneValueFilterConfig),
      new TeamReviewRequestedFilterProvider(providerRepositoryScope, noNoneValueFilterConfig),
    ]

    if (!scoped_repository) {
      filterProviders.push(new RepositoryFilterProvider({...noNoneValueFilterConfig, filterTypes: {multiKey: true}}))
      filterProviders.push(new OrgFilterProvider({...noNoneValueFilterConfig, priority: 6}))
    }

    if (sub_issues) {
      filterProviders.push(new ParentIssueFilterProvider(FILTER_KEYS.parentIssue, hasValueFilterConfig))
      filterProviders.push(new SubIssueFilterProvider(hasFilterEnabled))
    }

    return filterProviders
  }, [
    currentUser,
    issue_types,
    providerRepositoryScope,
    relayEnvironment,
    scoped_repository,
    sub_issues,
    issues_advanced_search,
    issues_advanced_search_has_filter,
  ])

  useEffect(() => {
    return () => {
      const typeFilterProvider = providers.find(isTypeFilterProvider)
      if (typeFilterProvider) {
        // Clean up cached issue type data from the store
        typeFilterProvider.requestDisposable?.dispose()
      }
    }
  }, [providers])

  const indexQuickFiltersEnabled = isFeatureEnabled('issues_react_index_quick_filters')

  return (
    <DynamicWrapper editing={editingContent}>
      {/* eslint-disable-next-line primer-react/direct-slot-children */}
      {editingContent && <FormControl.Label>{MESSAGES.query}</FormControl.Label>}
      <div className={`${styles.gap8} px-0 ${editingContent ? 'd-flex' : 'd-block'} flex-row flex-justify-between`}>
        <div className={`${styles.filterContainer} ${styles.gap8} d-flex flex-row flex-1 flexWrap min-width-0`}>
          <div className={`${styles.filter} d-flex flex-1 flex-column`}>
            <Filter
              id={viewId ?? 'search'}
              context={providerRepositoryScope ? {repo: providerRepositoryScope} : undefined}
              label={LABELS.issueSearchInputAriaLabel}
              placeholder={LABELS.issueSearchInputPlaceholder}
              onSubmit={onSubmit}
              onChange={onInputChange}
              providers={providers}
              inputRef={ref}
              filterValue={effectiveQuery}
              variant={'input'}
              settings={{aliasMatching: true, groupAndKeywordSupport: issues_advanced_search}}
              showValidationMessage={false}
              onValidation={onValidation}
            />
          </div>
          {!indexQuickFiltersEnabled && scoped_repository && !isNewIssuePath(pathname) && (
            <SearchBarActions currentRepository={currentRepository} />
          )}
          {validationMessage.length > 0 && (
            <div className={`${styles.validation} mt-1`}>
              <ValidationMessage messages={validationMessage} id="repository-validation-message" />
            </div>
          )}
        </div>
        {editingContent && (
          <div className={`${styles.gap8} d-flex flex-row`}>
            <Button onClick={onCancel}>{BUTTON_LABELS.cancel}</Button>
            <Button variant="primary" onClick={onUpdateViewQuery}>
              {BUTTON_LABELS.saveView}
            </Button>
          </div>
        )}
      </div>
    </DynamicWrapper>
  )
}
