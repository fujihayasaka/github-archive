import {noop} from '@github-ui/noop'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useState} from 'react'
import type {PreloadFetchPolicy} from 'react-relay'
import {useLocation} from 'react-router-dom'
import type {Environment} from 'relay-runtime'

import {VIEW_COLOR_FOREGROUND_MAP} from '../components/sidebar/ColorHelper'
import {CUSTOM_VIEW_ICONS_TO_PRIMER_ICON} from '../components/sidebar/IconHelper'
import useKnownViews from '../hooks/use-known-views'
import type {
  CreateDashboardSearchShortcutInput,
  createUserViewMutation$data,
} from '../mutations/__generated__/createUserViewMutation.graphql'
import type {
  SearchShortcutColor,
  SearchShortcutIcon,
  updateUserViewMutation$data,
} from '../mutations/__generated__/updateUserViewMutation.graphql'
import type {AppPayload} from '../types/app-payload'
import {issueRegexpWithoutDomain, issuesPathRegexp} from '../utils/urls'
import {VALUES} from '../constants/values'
import {QUERIES} from '@github-ui/query-builder/constants/queries'
import {LABELS} from '../constants/labels'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import {commitCreateUserViewMutation} from '../mutations/create-user-view-mutation'
import {commitUpdateUserViewMutation} from '../mutations/update-user-view-mutation'
import {useDebounce} from '@github-ui/use-debounce'

type ViewState = {
  viewName: string
  viewIcon: string
  viewDescription: string
  viewColor: string
  viewQuery: string
}

type QueryUpdateCallbacks = Partial<ViewState> & {
  viewId: string
  onSuccess?: (response: updateUserViewMutation$data) => void
  onError?: () => void
  relayEnvironment: Environment
}
type QueryCreateCallbacks = {
  onSuccess?: (response: createUserViewMutation$data) => void
  onError?: () => void
  relayEnvironment: Environment
}

type QueryDuplicateCallbacks = ViewState & {
  onSuccess?: (response: createUserViewMutation$data) => void
  onError?: () => void
  relayEnvironment: Environment
}

type QueryCreateCallbackInternal = {
  input: CreateDashboardSearchShortcutInput
  onSuccess?: (response: createUserViewMutation$data) => void
  onError?: () => void
  relayEnvironment: Environment
}

type QueryContextType = {
  // We have three different query states: the active query, the view query, and the search query.
  // Active is what's currently being searched, view is the parity of the saved view object, and
  // dirty represents the current text input of the search field.
  viewPosition: number | undefined
  setViewPosition: (q: number | undefined) => void
  isCustomView: (id: string) => boolean
  setIsEditing: (editing: boolean) => void
  isEditing: boolean
  isQueryLoading: boolean
  setIsQueryLoading: (loading: boolean) => void
  saveViewsConnectionId: string | undefined
  setSaveViewsConnectionId: (q: string) => void
  canEditView: boolean
  setCanEditView: (canEditView: boolean) => void
  activeSearchQuery: string
  setActiveSearchQuery: (query: string) => void
  isNewView: boolean
  setIsNewView: (isNewView: boolean) => void
  executeQuery: ((query: string, fetchPolicy?: PreloadFetchPolicy) => void) | undefined
  setExecuteQuery: (executeQuery: (query: string) => void) => void
  dirtyViewId: string | undefined
  setDirtyViewId: (viewId: string | undefined) => void
  currentViewId: string
  setCurrentViewId: (viewId: string) => void
  currentPage: number | undefined
  setCurrentPage: (page: number | undefined) => void
  savedViewsCount: number
  setSavedViewsCount: (count: number) => void
}

type QueryEditContextType = {
  commitUserViewCreate: ({onSuccess, onError, relayEnvironment}: QueryCreateCallbacks) => void
  commitUserViewDuplicate: ({
    onSuccess,
    onError,
    viewName,
    viewIcon,
    viewDescription,
    viewColor,
    viewQuery,
  }: QueryDuplicateCallbacks) => void
  commitUserViewEdit: ({viewId, onSuccess, onError, relayEnvironment}: QueryUpdateCallbacks) => void
  dirtySearchQuery: string | null
  setDirtySearchQuery: (q: string | null) => void
  debouncedDirtySearchQuery: string | null
  dirtyTitle: string | null
  setDirtyTitle: (title: string | null) => void
  dirtyDescription: string | null
  setDirtyDescription: (description: string | null) => void
  dirtyViewIcon: string | null
  setDirtyViewIcon: (icon: string | null) => void
  dirtyViewColor: string | null
  setDirtyViewColor: (color: string | null) => void
  bulkJobId: string | null
  setBulkJobId: (bulkJobId: string | null) => void
  clearSavedViewEditState: () => void
  shouldFocusSearchOnNav: boolean
  setShouldFocusSearchOnNav: (shouldFocus: boolean) => void
}

type QueryContextProviderType = {
  children: ReactNode
}

const QueryContext = createContext<QueryContextType>({
  viewPosition: undefined,
  setViewPosition: noop,
  isCustomView: (id: string) => id === '',
  isEditing: false,
  setIsEditing: noop,
  isQueryLoading: false,
  setIsQueryLoading: noop,
  saveViewsConnectionId: undefined,
  setSaveViewsConnectionId: noop,
  activeSearchQuery: '',
  setActiveSearchQuery: noop,
  canEditView: false,
  setCanEditView: noop,
  isNewView: false,
  setIsNewView: noop,
  executeQuery: undefined,
  setExecuteQuery: noop,
  dirtyViewId: undefined,
  setDirtyViewId: noop,
  currentViewId: VIEW_IDS.empty,
  setCurrentViewId: noop,
  currentPage: undefined,
  setCurrentPage: noop,
  savedViewsCount: 0,
  setSavedViewsCount: noop,
})

const QueryEditContext = createContext<QueryEditContextType>({
  commitUserViewCreate: noop,
  commitUserViewEdit: noop,
  commitUserViewDuplicate: noop,
  dirtySearchQuery: '',
  debouncedDirtySearchQuery: null,
  setDirtySearchQuery: noop,
  dirtyTitle: '',
  setDirtyTitle: noop,
  dirtyDescription: '',
  setDirtyDescription: noop,
  dirtyViewIcon: null,
  setDirtyViewIcon: noop,
  dirtyViewColor: null,
  setDirtyViewColor: noop,
  bulkJobId: null,
  setBulkJobId: noop,
  clearSavedViewEditState: noop,
  shouldFocusSearchOnNav: false,
  setShouldFocusSearchOnNav: noop,
})

// This is a deprecated method that we used when we implemented CustomViews on issues dashboard
// The method should return VIEW_IDS.repository when we're on the repo level in any of new/choose/show/index actions
// It should otherwise return the id of the view that you're on - when coming from the dashboard page
const useInitialViewId = () => {
  const {scoped_repository} = useAppPayload<AppPayload>()
  const {pathname} = useLocation()
  if (pathname.match(issueRegexpWithoutDomain)) {
    return scoped_repository ? VIEW_IDS.repository : VIEW_IDS.assignedToMe
  }
  const id = pathname.split('/').pop() || ''

  if (scoped_repository && pathname.match(issuesPathRegexp)) {
    return VIEW_IDS.repository
  }

  return id === 'issues' || !id ? VIEW_IDS.empty : id
}

export function QueryContextProvider({children}: QueryContextProviderType) {
  const {
    initial_view_content: {can_edit_view: initialCanEditView},
  } = useAppPayload<AppPayload>()

  const {addToast} = useToastContext()
  const {search} = useLocation()
  const urlSearchParams = new URLSearchParams(search)
  const queryParam = urlSearchParams.get('q')
  const urlQuery = !queryParam || queryParam === '' ? QUERIES.defaultRepoLevelOpen : queryParam

  const [canEditView, setCanEditView] = useState(initialCanEditView)
  const [dirtyViewQuery, setDirtyViewQuery] = useState<string | null>(null)
  const [activeSearchQuery, setActiveSearchQuery] = useState<string>(urlQuery)
  const [viewPosition, setViewPosition] = useState<number | undefined>(undefined)
  const [saveViewsConnectionId, setSaveViewsConnectionId] = useState<string | undefined>(undefined)
  const [dirtyTitle, setDirtyTitle] = useState<string | null>(null)
  const [dirtyDescription, setDirtyDescription] = useState<string | null>(null)
  const [dirtyViewIcon, setDirtyViewIcon] = useState<string | null>(null)
  const [dirtyViewColor, setDirtyViewColor] = useState<string | null>(null)
  const [dirtyViewId, setDirtyViewId] = useState<string | undefined>(undefined)
  const initialViewId = useInitialViewId()
  const [currentViewId, setCurrentViewId] = useState<string>(initialViewId)
  const [isEditing, setIsEditing] = useState<boolean>(false)
  const [isQueryLoading, setIsQueryLoading] = useState<boolean>(false)
  const [isNewView, setIsNewView] = useState<boolean>(false)
  const {knownViews} = useKnownViews()
  const [currentPage, setCurrentPage] = useState<number | undefined>()
  const [executeQuery, setExecuteQuery] = useState<((query: string) => void) | undefined>()
  const [shouldFocusSearchOnNav, setShouldFocusSearchOnNav] = useState(false)
  const [savedViewsCount, setSavedViewsCount] = useState(0)
  const [debouncedDirtySearchQuery, setDebouncedDirtySearchQuery] = useState<string | null>(null)

  // To enable 'syncing' of the list pickers selected value and the _not yet submitted_ dirty search query
  // we need to debounce the dirty search query. This is because the list pickers attempt to fetch their data
  // when a pre-selected value is present and we don't want to trigger on every keystroke.
  const debouncedSetDebouncedDirtySearchQuery = useDebounce(setDebouncedDirtySearchQuery, 500)

  useEffect(() => {
    debouncedSetDebouncedDirtySearchQuery(dirtyViewQuery)
  }, [debouncedSetDebouncedDirtySearchQuery, dirtyViewQuery])

  const [bulkJobId, setBulkJobId] = useLocalStorage<string | null>(VALUES.localStorageKeyBulkUpdateIssues, null)

  const isCustomView = useCallback(
    (viewId: string | undefined) => {
      if (!viewId) return false
      return knownViews.findIndex(s => s.id === viewId) === -1
    },
    [knownViews],
  )

  const clearSavedViewEditState = useCallback(() => {
    setDirtyViewQuery(null)
    setDirtyTitle(null)
    setDirtyDescription(null)
    setDirtyViewIcon(null)
    setDirtyViewColor(null)
    setDirtyViewId(undefined)
    setShouldFocusSearchOnNav(false)
  }, [])

  const commitUserViewEdit = useCallback(
    ({
      viewId,
      viewName,
      viewIcon,
      viewColor,
      viewDescription,
      viewQuery,
      onSuccess,
      onError,
      relayEnvironment,
    }: QueryUpdateCallbacks) => {
      if (!isCustomView(viewId)) return

      commitUpdateUserViewMutation({
        environment: relayEnvironment,
        input: {
          shortcutId: viewId,
          query: viewQuery,
          name: viewName,
          description: viewDescription,
          icon: viewIcon as SearchShortcutIcon,
          color: viewColor as SearchShortcutColor,
        },
        onError: () => {
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: LABELS.views.updateError,
          })
          onError?.()
        },
        onCompleted: (response: updateUserViewMutation$data) => {
          onSuccess?.(response)
        },
      })
    },
    [isCustomView, addToast],
  )

  const internalCommitViewCreate = useCallback(
    ({input, onSuccess, onError, relayEnvironment}: QueryCreateCallbackInternal) => {
      input.name = input.name || LABELS.views.defaultName
      input.query = input.query === null || input.query === undefined ? dirtyViewQuery : input.query

      return commitCreateUserViewMutation({
        environment: relayEnvironment,
        input,
        onError: () => {
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: LABELS.views.createError,
          })
          onError?.()
        },
        onCompleted: response => {
          onSuccess?.(response)
        },
      })
    },
    [dirtyViewQuery, addToast],
  )

  const commitUserViewCreate = useCallback(
    ({onSuccess, onError, relayEnvironment}: QueryCreateCallbacks) => {
      return internalCommitViewCreate({
        input: {
          query: VALUES.defaultQueryForNewView,
          name: LABELS.views.defaultName,
          searchType: 'ISSUES',
          icon: VALUES.defaultViewIcon as SearchShortcutIcon,
          color: VALUES.defaultViewColor as SearchShortcutColor,
        },
        onSuccess,
        onError,
        relayEnvironment,
      })
    },
    [internalCommitViewCreate],
  )

  const commitUserViewDuplicate = useCallback(
    ({
      onSuccess,
      onError,
      viewName,
      viewIcon,
      viewColor,
      viewDescription,
      viewQuery,
      relayEnvironment,
    }: QueryDuplicateCallbacks) => {
      return internalCommitViewCreate({
        input: {
          query: viewQuery,
          name: `${viewName} copy`,
          description: viewDescription,
          color: (VIEW_COLOR_FOREGROUND_MAP[viewColor] ? viewColor : VALUES.defaultViewColor) as SearchShortcutColor,
          icon: (CUSTOM_VIEW_ICONS_TO_PRIMER_ICON[viewIcon] ? viewIcon : VALUES.defaultViewIcon) as SearchShortcutIcon,
          searchType: 'ISSUES',
        },
        onSuccess,
        onError,
        relayEnvironment,
      })
    },
    [internalCommitViewCreate],
  )

  const queryContextValue = useMemo<QueryContextType>(() => {
    return {
      isEditing,
      setIsEditing,
      isQueryLoading,
      setIsQueryLoading,
      viewPosition,
      setViewPosition,
      isCustomView,
      saveViewsConnectionId,
      setSaveViewsConnectionId,
      activeSearchQuery,
      setActiveSearchQuery,
      canEditView,
      setCanEditView,
      isNewView,
      setIsNewView,
      executeQuery,
      setExecuteQuery,
      dirtyViewId,
      setDirtyViewId,
      currentViewId,
      setCurrentViewId,
      currentPage,
      setCurrentPage,
      savedViewsCount,
      setSavedViewsCount,
    }
  }, [
    isEditing,
    isQueryLoading,
    viewPosition,
    isCustomView,
    saveViewsConnectionId,
    activeSearchQuery,
    canEditView,
    isNewView,
    executeQuery,
    dirtyViewId,
    currentViewId,
    currentPage,
    savedViewsCount,
  ])

  const queryEditContextValue = useMemo<QueryEditContextType>(() => {
    return {
      commitUserViewCreate,
      commitUserViewDuplicate,
      commitUserViewEdit,
      dirtySearchQuery: dirtyViewQuery,
      setDirtySearchQuery: setDirtyViewQuery,
      debouncedDirtySearchQuery,
      dirtyDescription,
      setDirtyDescription,
      dirtyViewIcon,
      setDirtyViewIcon,
      dirtyTitle,
      setDirtyTitle,
      dirtyViewColor,
      setDirtyViewColor,
      dirtyViewId,
      setDirtyViewId,
      bulkJobId,
      setBulkJobId,
      clearSavedViewEditState,
      shouldFocusSearchOnNav,
      setShouldFocusSearchOnNav,
    }
  }, [
    commitUserViewCreate,
    commitUserViewDuplicate,
    commitUserViewEdit,
    dirtyViewQuery,
    debouncedDirtySearchQuery,
    dirtyDescription,
    dirtyViewIcon,
    dirtyTitle,
    dirtyViewColor,
    dirtyViewId,
    bulkJobId,
    setBulkJobId,
    clearSavedViewEditState,
    shouldFocusSearchOnNav,
  ])

  return (
    <QueryContext.Provider value={queryContextValue}>
      <QueryEditContext.Provider value={queryEditContextValue}>{children}</QueryEditContext.Provider>
    </QueryContext.Provider>
  )
}

export function useQueryContext() {
  return useContext(QueryContext)
}

export function useQueryEditContext() {
  return useContext(QueryEditContext)
}
