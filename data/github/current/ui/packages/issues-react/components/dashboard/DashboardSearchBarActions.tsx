import {searchUrl} from '@github-ui/issue-url-helper'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {BookmarkIcon, DuplicateIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {useCallback} from 'react'
import {graphql, useFragment, useRelayEnvironment} from 'react-relay'
import {LABELS} from '../../constants/labels'
import {VALUES} from '../../constants/values'
import {useQueryContext, useQueryEditContext} from '../../contexts/QueryContext'
import {useAppNavigate} from '../../hooks/use-app-navigate'
import type {DashboardSearchBarActionsFragment$key} from './__generated__/DashboardSearchBarActionsFragment.graphql'
import styles from './DashboardSearchBarActions.module.css'

type SearchBarProps = {
  currentView: DashboardSearchBarActionsFragment$key
  queryFromCustomView?: string | null
}

export function DashboardSearchBarActions({currentView}: SearchBarProps) {
  const {
    id: viewId,
    name: viewName,
    query: viewQuery,
    description: viewDescription,
    color: viewColor,
    icon: viewIcon,
  } = useFragment(
    graphql`
      fragment DashboardSearchBarActionsFragment on Shortcutable {
        id
        name
        description
        icon
        color
        query
      }
    `,
    currentView,
  )

  const relayEnvironment = useRelayEnvironment()
  const {addToast} = useToastContext()
  const {isCustomView, canEditView, savedViewsCount} = useQueryContext()
  const {navigateToSavedView, navigateToUrl} = useAppNavigate()
  const {commitUserViewDuplicate, commitUserViewEdit, dirtySearchQuery} = useQueryEditContext()

  const canDuplicateView = viewId !== VIEW_IDS.repository && (canEditView || !isCustomView)
  const canModifyCustomView = isCustomView(viewId) && canEditView
  const queryEditActive = dirtySearchQuery !== null && viewQuery?.trim() !== dirtySearchQuery?.trim()
  const maxViewsReached = savedViewsCount >= VALUES.viewsPageSize

  const duplicateView = useCallback(() => {
    const newQuery = dirtySearchQuery === null ? viewQuery : dirtySearchQuery

    const args = {
      viewName,
      viewIcon,
      viewColor,
      viewDescription,
      viewQuery: newQuery,
      onError: () =>
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: LABELS.views.duplicateError,
        }),
      relayEnvironment,
    }

    commitUserViewDuplicate({
      ...args,
      onSuccess: ({createDashboardSearchShortcut}) => {
        if (createDashboardSearchShortcut?.shortcut) {
          navigateToSavedView(createDashboardSearchShortcut.shortcut.id, {isEditing: false})
        }
      },
    })
  }, [
    dirtySearchQuery,
    viewQuery,
    viewName,
    viewIcon,
    viewColor,
    viewDescription,
    relayEnvironment,
    commitUserViewDuplicate,
    addToast,
    navigateToSavedView,
  ])

  const saveQueryUpdate = useCallback(() => {
    const newQuery = dirtySearchQuery === null ? viewQuery : dirtySearchQuery

    const args = {
      viewId,
      viewQuery: newQuery,
      viewName,
      viewIcon,
      viewColor,
      viewDescription,
      onSuccess: () => {
        const url = searchUrl({viewId})
        navigateToUrl(url)
      },
      relayEnvironment,
    }

    commitUserViewEdit(args)
  }, [
    dirtySearchQuery,
    viewQuery,
    viewId,
    viewName,
    viewIcon,
    viewColor,
    viewDescription,
    relayEnvironment,
    commitUserViewEdit,
    navigateToUrl,
  ])

  const actions = [
    {
      icon: <BookmarkIcon />,
      text: 'Save changes',
      onSelect: saveQueryUpdate,
      enabled: canModifyCustomView,
    },
    {
      icon: <DuplicateIcon />,
      text: `Save changes to new view`,
      onSelect: duplicateView,
      enabled: canDuplicateView && !maxViewsReached,
      showDescription: Boolean(canDuplicateView && maxViewsReached),
      description: LABELS.views.maxViewsReached,
    },
  ]

  return (
    <div className={styles.searchBarContainer}>
      <ActionMenu>
        <ActionMenu.Button disabled={!queryEditActive || !canModifyCustomView}>Save</ActionMenu.Button>
        <ActionMenu.Overlay className={styles.menuOverlay}>
          <ActionList>
            {actions.map(action => {
              return (
                <ActionList.Item key={action.text} onSelect={action.onSelect} disabled={!action.enabled}>
                  <ActionList.LeadingVisual>{action.icon}</ActionList.LeadingVisual>
                  {action.text}
                  {action.showDescription && (
                    <ActionList.Description variant="block">
                      <span className={styles.warning}>{action.description}</span>
                    </ActionList.Description>
                  )}
                </ActionList.Item>
              )
            })}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </div>
  )
}
