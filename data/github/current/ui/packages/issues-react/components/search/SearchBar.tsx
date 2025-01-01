import {Filter, type FilterQuery, SubmitEvent, ValidationMessage} from '@github-ui/filter'

import {HOTKEYS} from '@github-ui/issue-viewer/Hotkeys'

import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {ModifierKeys, useKeyPress} from '@github-ui/use-key-press'
import {FormControl} from '@primer/react'
import {type PropsWithChildren, type ReactNode, useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {graphql, useFragment} from 'react-relay'
import {useLocation, useParams} from 'react-router-dom'

import {isFeatureEnabled} from '@github-ui/feature-flags'
import {searchUrl} from '@github-ui/issue-url-helper'
import {LABELS} from '../../constants/labels'
import {MESSAGES} from '../../constants/messages'
import {CUSTOM_VIEW, DEFAULT_QUERY, EMPTY_VIEW, KNOWN_VIEWS, REPOSITORY_VIEW} from '../../constants/view-constants'
import {useQueryContext, useQueryEditContext} from '../../contexts/QueryContext'
import {useAppNavigate} from '../../hooks/use-app-navigate'
import {useHyperlistAnalytics} from '../../hooks/use-hyperlist-analytics'
import type {AppPayload} from '../../types/app-payload'
import {
  isCreatedByAppIssuePathForRepo,
  isCustomViewIssuePathForRepo,
  isNewIssuePath,
  removeInvalidFiltersFromQuery,
} from '../../utils/urls'
import styles from './SearchBar.module.css'
import {SearchBarActions} from './SearchBarActions'
import type {SearchBarCurrentViewFragment$key} from './__generated__/SearchBarCurrentViewFragment.graphql'

import type {SearchBarRepo$key} from './__generated__/SearchBarRepo.graphql'
import {useFilterProviders} from './providers/use-filter-providers'

type SearchBarProps = {
  currentViewKey: SearchBarCurrentViewFragment$key
  currentRepository: SearchBarRepo$key | null
  queryFromCustomView?: string | null
}

const DynamicWrapper = ({editing, children}: {editing: boolean; children: ReactNode}) => {
  return editing ? <FormControl sx={{alignItems: 'normal'}}>{children}</FormControl> : <>{children}</>
}

function withTrailingSpace(query: string) {
  return query ? `${query.trim()} ` : ''
}

export function SearchBar({
  currentViewKey,
  currentRepository,
  queryFromCustomView,
  children,
}: PropsWithChildren<SearchBarProps>) {
  const ref = useRef<HTMLInputElement>(null)

  const {setActiveSearchQuery, isCustomView, isEditing, setCurrentPage} = useQueryContext()

  const [validationMessage, setValidationMessage] = useState<string[]>([])

  const {search, pathname} = useLocation()

  const urlSearchParams = new URLSearchParams(search)
  const urlQuery = urlSearchParams.get('q')

  const {scoped_repository, current_user_settings} = useAppPayload<AppPayload>()

  const {navigateToUrl} = useAppNavigate()

  // GenericView is a union type between team and user search shortcut
  // Adding this here resulted in possible null values for the returned props
  // It should not be the case
  const {
    id: viewId,
    scopingRepository,
    query,
  } = useFragment<SearchBarCurrentViewFragment$key>(
    graphql`
      fragment SearchBarCurrentViewFragment on Shortcutable {
        id
        name
        query
        scopingRepository {
          name
          owner {
            login
          }
        }
      }
    `,
    currentViewKey,
  )

  const currentRepositoryData = useFragment(
    graphql`
      fragment SearchBarRepo on Repository {
        isInOrganization
        ...SearchBarActionsRepositoryFragment
      }
    `,
    currentRepository,
  )

  // This is legacy behavior found in repos/issues search
  const {author, assignee, mentioned, label} = useParams<{
    author: string
    assignee: string
    mentioned: string
    label: string
  }>()
  const customViewQuery = `${CUSTOM_VIEW.defaultQuery} ${CUSTOM_VIEW.query({
    author,
    assignee,
    mentioned,
    label,
    createdByApp: isCreatedByAppIssuePathForRepo(pathname),
  })}`
  const viewQuery = isCustomViewIssuePathForRepo(pathname) ? customViewQuery : query

  const originalQuery = scopingRepository
    ? `repo:${scopingRepository.owner.login}/${scopingRepository.name} ${viewQuery}`
    : viewQuery

  const {dirtySearchQuery, setDirtySearchQuery, setShouldFocusSearchOnNav, shouldFocusSearchOnNav} =
    useQueryEditContext()

  const setCurrentQuery = useCallback(
    (currentQuery: string) => {
      setActiveSearchQuery(currentQuery)
      setDirtySearchQuery(null)
    },
    [setActiveSearchQuery, setDirtySearchQuery],
  )

  useEffect(() => {
    if (!isNewIssuePath(pathname)) {
      const currentQuery = urlQuery || originalQuery || ''
      setActiveSearchQuery(currentQuery)

      if (urlQuery) {
        setDirtySearchQuery(urlQuery)
      }
    }
  }, [setCurrentQuery, urlQuery, pathname, originalQuery, setActiveSearchQuery, setDirtySearchQuery])

  const {sendHyperlistAnalyticsEvent} = useHyperlistAnalytics()

  const filterProviders = useFilterProviders({isOrgScope: !!currentRepositoryData?.isInOrganization})

  const onSubmit = useCallback(
    (request: FilterQuery, event: SubmitEvent) => {
      let searchQuery = request.raw
      if (event === SubmitEvent.Clear) {
        searchQuery = originalQuery
        setCurrentQuery(originalQuery)
      }

      let finalQuery = (searchQuery ? searchQuery : DEFAULT_QUERY).trim()

      const filterConfig = request.config
      // when the filter is using the parser v2 that supports the advanced search grammar,
      // the query is already validated by this point and incompatible with the following sanitization
      if (!filterConfig.groupAndKeywordSupport) {
        finalQuery = removeInvalidFiltersFromQuery(searchQuery)
      }
      sendHyperlistAnalyticsEvent('search.execute', 'FILTER_BAR_INPUT', {new_query: finalQuery})

      const url = searchUrl({viewId, query: finalQuery})

      navigateToUrl(url, {preventAutofocus: true})
      setCurrentPage(1)
    },
    [sendHyperlistAnalyticsEvent, navigateToUrl, setCurrentPage, originalQuery, setCurrentQuery, viewId],
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

  const onInputChange = useCallback(
    (filter: string) => {
      setDirtySearchQuery(filter.trim())
    },
    [setDirtySearchQuery],
  )

  const onValidation = useCallback((messages: string[]) => setValidationMessage(messages), [setValidationMessage])

  useKeyPress([HOTKEYS.focusSearch], onShortcutKeyPress, {[ModifierKeys.metaKey]: true})
  useKeyPress([HOTKEYS.focusSearch], onShortcutKeyPress, {[ModifierKeys.ctrlKey]: true})

  // We can only get into a valid edit state if details are not being shown for a custom view header
  const editingContent = isEditing && isCustomView(viewId)

  useEffect(() => {
    if (!ref.current || !editingContent) return

    const input = ref.current

    function handleFocus() {
      setShouldFocusSearchOnNav(true)
    }

    input.addEventListener('focus', handleFocus)

    return () => input.removeEventListener('focus', handleFocus)
  }, [editingContent, setShouldFocusSearchOnNav])

  useEffect(() => {
    if (editingContent && ref.current && shouldFocusSearchOnNav) {
      requestAnimationFrame(() => {
        if (ref.current) {
          ref.current.focus()
          const queryLength = ref.current.value?.length || 0
          ref.current.setSelectionRange(queryLength, queryLength)
        }
      })
    }
  }, [editingContent, shouldFocusSearchOnNav])

  const queryFromViewId = isCustomViewIssuePathForRepo(pathname)
    ? customViewQuery
    : [...KNOWN_VIEWS, EMPTY_VIEW].find(v => v.id === viewId)?.query

  // In a repo index, we give precendence to the query from the URL over the query from the viewId
  const effectiveQueryFromViewId = useMemo(
    () => (viewId === REPOSITORY_VIEW.id ? urlQuery ?? queryFromViewId : queryFromViewId ?? urlQuery),
    [queryFromViewId, urlQuery, viewId],
  )
  const effectiveQuery = useMemo(() => {
    return dirtySearchQuery ?? effectiveQueryFromViewId ?? queryFromCustomView ?? ''
  }, [dirtySearchQuery, effectiveQueryFromViewId, queryFromCustomView])

  const providerRepositoryScope = scoped_repository ? `${scoped_repository.owner}/${scoped_repository.name}` : undefined

  const indexQuickFiltersEnabled = isFeatureEnabled('issues_react_index_quick_filters')

  let showClearButton = false

  // This should be reworked along with the many different variables we have that represent _some_ type of query input
  // For now, this ensures the clear button works correctly in all surfaces areas, but ideally, search bar shouldn't
  // be concerned with almost _any_ of these special cases.
  if (isCustomView(viewId)) {
    // Issues Dashboard Custom (Saved) View - i.e. github.com/issues
    showClearButton = dirtySearchQuery?.trim() !== queryFromCustomView?.trim()
  } else if (viewId === REPOSITORY_VIEW.id) {
    // Repository / Issues Search - i.e. github.com/github/issues
    showClearButton = dirtySearchQuery?.trim() !== queryFromViewId?.trim()
  } else {
    // Issues Dashboard Known (Custom) View - i.e. github.com/issues/assigned
    showClearButton = dirtySearchQuery?.trim() !== effectiveQueryFromViewId?.trim()
  }

  return (
    <DynamicWrapper editing={editingContent}>
      {/* eslint-disable-next-line primer-react/direct-slot-children */}
      {editingContent && <FormControl.Label visuallyHidden>{MESSAGES.query}</FormControl.Label>}
      <div className={`${styles.gap8} px-0 ${editingContent ? 'd-flex' : 'd-block'} flex-row flex-justify-between`}>
        <div className={`${styles.filterContainer} ${styles.gap8} d-flex flex-row flex-1 flexWrap min-width-0`}>
          <div className={`${styles.filter} d-flex flex-1 flex-column`}>
            <Filter
              id={viewId ?? 'search'}
              context={providerRepositoryScope ? {repo: providerRepositoryScope} : undefined}
              label={editingContent ? LABELS.issueEditingSearchInputAriaLabel : LABELS.issueSearchInputAriaLabel}
              visuallyHideLabel={!editingContent}
              placeholder={LABELS.issueSearchInputPlaceholder}
              onSubmit={onSubmit}
              onChange={onInputChange}
              providers={filterProviders}
              inputRef={ref}
              filterValue={withTrailingSpace(effectiveQuery)}
              variant={'input'}
              settings={{aliasMatching: true, groupAndKeywordSupport: true}}
              showValidationMessage={false}
              onValidation={onValidation}
              showClearButton={dirtySearchQuery !== null && showClearButton}
            />
          </div>

          {children}

          {!indexQuickFiltersEnabled && scoped_repository && !isNewIssuePath(pathname) && (
            <SearchBarActions currentRepository={currentRepositoryData} />
          )}

          {validationMessage.length > 0 && (
            <div className={`${styles.validation} mt-1`}>
              <ValidationMessage messages={validationMessage} id="repository-validation-message" />
            </div>
          )}
        </div>
      </div>
    </DynamicWrapper>
  )
}
