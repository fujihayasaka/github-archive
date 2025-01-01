import {updateUrl} from '@github-ui/history'
import {searchUrl} from '@github-ui/issue-url-helper'
import {Button} from '@primer/react'
import {useCallback} from 'react'
import {graphql, useFragment, useRelayEnvironment} from 'react-relay'
import {useLocation, useParams} from 'react-router-dom'
import {BUTTON_LABELS} from '../../constants/buttons'
import {ASSIGNED_TO_ME_VIEW, CUSTOM_VIEW} from '../../constants/view-constants'
import {useQueryContext, useQueryEditContext} from '../../contexts/QueryContext'
import {useHyperlistAnalytics} from '../../hooks/use-hyperlist-analytics'
import {isCreatedByAppIssuePathForRepo, isCustomViewIssuePathForRepo} from '../../utils/urls'
import styles from './DashboardEditViewActions.module.css'
import type {DashboardEditViewActionsFragment$key} from './__generated__/DashboardEditViewActionsFragment.graphql'
import {noop} from '@github-ui/noop'
import {commitRemoveUserViewMutation} from '../../mutations/remove-user-view-mutation'
import {useAppNavigate} from '../../hooks/use-app-navigate'
import {isDirty} from '../../utils/type-predicates'

type DashboardEditViewActionsProps = {
  currentView: DashboardEditViewActionsFragment$key
}

export function DashboardEditViewActions({currentView}: DashboardEditViewActionsProps) {
  const {
    id: viewId,
    color: viewColor,
    name: viewName,
    description: viewDescription,
    icon: viewIcon,
    scopingRepository,
    query,
  } = useFragment<DashboardEditViewActionsFragment$key>(
    graphql`
      fragment DashboardEditViewActionsFragment on Shortcutable {
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

  const relayEnvironment = useRelayEnvironment()
  const {pathname} = useLocation()
  const {navigateToView} = useAppNavigate()

  const {setIsEditing, setIsNewView, dirtyViewId, isNewView} = useQueryContext()

  const {
    dirtyTitle,
    dirtyDescription,
    commitUserViewEdit,
    dirtySearchQuery,
    dirtyViewIcon,
    dirtyViewColor,
    clearSavedViewEditState,
  } = useQueryEditContext()

  const {sendHyperlistAnalyticsEvent} = useHyperlistAnalytics()

  const {author, assignee, mentioned} = useParams<{author: string; assignee: string; mentioned: string}>()

  const customViewQuery = `${CUSTOM_VIEW.defaultQuery} ${CUSTOM_VIEW.query({
    author,
    assignee,
    mentioned,
    createdByApp: isCreatedByAppIssuePathForRepo(pathname),
  })}`

  const viewQuery = isCustomViewIssuePathForRepo(pathname) ? customViewQuery : query

  const originalQuery = scopingRepository
    ? `repo:${scopingRepository.owner.login}/${scopingRepository.name} ${viewQuery}`
    : `${viewQuery}`

  const onUpdateViewQuery = useCallback(() => {
    // In a future world, we should consider using a true edit / create form that manages this for us.
    const updatedViewState = {
      viewName: isDirty(dirtyTitle) ? dirtyTitle : viewName,
      viewDescription: isDirty(dirtyDescription) ? dirtyDescription : viewDescription,
      viewIcon: isDirty(dirtyViewIcon) ? dirtyViewIcon : viewIcon,
      viewColor: isDirty(dirtyViewColor) ? dirtyViewColor : viewColor,
      viewQuery: isDirty(dirtySearchQuery) ? dirtySearchQuery : originalQuery,
    }

    if (updatedViewState.viewName.trim() !== '') {
      sendHyperlistAnalyticsEvent('search.save', 'FILTER_BAR_SAVE_BUTTON', {
        new_color: updatedViewState.viewColor,
        new_icon: updatedViewState.viewIcon,
        new_query: updatedViewState.viewQuery,
        new_view_description: updatedViewState.viewDescription,
        new_view_name: updatedViewState.viewName,
        prev_color: viewColor,
        prev_icon: viewIcon,
        prev_query: originalQuery,
        prev_view_description: viewDescription,
        prev_view_name: viewName,
      })

      const args = {
        viewId,
        ...updatedViewState,
        onSuccess: () => {
          const url = searchUrl({viewId})
          updateUrl(url)
          setIsEditing(false)
        },
        relayEnvironment,
      }

      commitUserViewEdit(args)

      setIsNewView(false)
      clearSavedViewEditState()
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
    originalQuery,
    viewDescription,
    viewName,
    viewId,
    relayEnvironment,
    commitUserViewEdit,
    setIsNewView,
    clearSavedViewEditState,
    setIsEditing,
  ])

  const deleteDirtyView = useCallback(() => {
    if (dirtyViewId === undefined) {
      return
    }

    const payload = {
      environment: relayEnvironment,
      input: {shortcutId: dirtyViewId},
      onError: () => noop,
      onCompleted: () => {
        navigateToView({viewId: ASSIGNED_TO_ME_VIEW.id, canEditView: true})
      },
    }

    commitRemoveUserViewMutation(payload)
  }, [dirtyViewId, navigateToView, relayEnvironment])

  const onCancel = useCallback(() => {
    setIsEditing(false)

    if (isNewView) {
      deleteDirtyView()
    }

    setIsNewView(false)
    clearSavedViewEditState()

    navigateToView({viewId, canEditView: true})
  }, [setIsEditing, isNewView, setIsNewView, clearSavedViewEditState, navigateToView, viewId, deleteDirtyView])

  return (
    <div className={`${styles.gap8} d-flex flex-row`}>
      <Button onClick={onCancel}>{BUTTON_LABELS.cancel}</Button>
      <Button variant="primary" onClick={onUpdateViewQuery}>
        {BUTTON_LABELS.saveView}
      </Button>
    </div>
  )
}
