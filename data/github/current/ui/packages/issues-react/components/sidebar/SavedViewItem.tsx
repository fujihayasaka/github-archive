import {useNavigate} from '@github-ui/use-navigate'
import {NavList, useConfirm} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {useCallback} from 'react'
import {Link} from 'react-router-dom'

import {LABELS} from '../../constants/labels'
import {useQueryContext, useQueryEditContext} from '../../contexts/QueryContext'
import {useNavigationContext} from '../../contexts/NavigationContext'
import {searchUrl} from '@github-ui/issue-url-helper'
import {iconToPrimerIcon} from './IconHelper'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import type {Icon} from '@primer/octicons-react'
import styles from './SavedViewItem.module.css'
import {useAppNavigate} from '../../hooks/use-app-navigate'
import {noop} from '@github-ui/noop'
import {commitRemoveUserViewMutation} from '../../mutations/remove-user-view-mutation'
import {useRelayEnvironment} from 'react-relay'

type Props = {
  id?: string
  icon?: string
  // progressively migrate to Icon
  Icon?: Icon
  color: string
  title: string
  description?: string
  query?: string
  position: number
}

export function SavedViewItem({id, icon, Icon, color, title, position, query}: Props) {
  const {
    setViewPosition,
    setCanEditView,
    isNewView,
    setIsNewView,
    setCurrentPage,
    currentViewId,
    setIsEditing,
    dirtyViewId,
  } = useQueryContext()
  const {dirtyDescription, dirtySearchQuery, dirtyTitle, clearSavedViewEditState} = useQueryEditContext()
  const {closeNavigation} = useNavigationContext()
  const {navigateToUrl} = useAppNavigate()
  const relayEnvironment = useRelayEnvironment()

  const navigate = useNavigate()
  const confirm = useConfirm()
  const isCurrent = id === currentViewId
  const url = searchUrl({viewId: id, query})

  const scopedRepoSubmitQuery = useCallback(async () => {
    navigateToUrl(url)
    setCurrentPage(1)
  }, [navigateToUrl, url, setCurrentPage])

  const deleteDirtyView = useCallback(() => {
    if (dirtyViewId === undefined) {
      return
    }

    const payload = {
      environment: relayEnvironment,
      input: {shortcutId: dirtyViewId},
      onError: noop,
      onCompleted: noop,
    }

    commitRemoveUserViewMutation(payload)
  }, [dirtyViewId, relayEnvironment])

  const submitQuery = useCallback(async () => {
    // In a repo's index, we don't want to navigate, just update the query
    // and update the UI
    if (id === VIEW_IDS.repository) {
      return scopedRepoSubmitQuery()
    }

    // When navigating to a different saved view while the user is editing a newly created view
    if (isNewView && (dirtyTitle !== LABELS.views.defaultName || dirtySearchQuery !== '' || dirtyDescription !== '')) {
      const discardChanges = await confirm({
        title: LABELS.views.unsavedChangesTitle,
        content: LABELS.views.unsavedChangesContent,
        confirmButtonType: 'danger',
      })

      if (!discardChanges) {
        return
      }

      deleteDirtyView()
    }

    setIsEditing(false)
    setIsNewView(false)
    navigate(url)

    clearSavedViewEditState()

    setViewPosition(position)
    setCanEditView(true)
    closeNavigation()
  }, [
    id,
    isNewView,
    dirtyTitle,
    dirtySearchQuery,
    dirtyDescription,
    setIsEditing,
    setIsNewView,
    navigate,
    url,
    clearSavedViewEditState,
    setViewPosition,
    position,
    setCanEditView,
    closeNavigation,
    scopedRepoSubmitQuery,
    confirm,
    deleteDirtyView,
  ])

  const onSelect = useCallback(
    (event: React.MouseEvent | React.KeyboardEvent<HTMLElement>) => {
      submitQuery()
      event.preventDefault()
      event.stopPropagation()
    },
    [submitQuery],
  )

  return (
    <NavList.Item
      to={url}
      as={Link}
      aria-current={isCurrent ? 'page' : undefined}
      onClick={onSelect}
      className={styles.navItem}
    >
      <div className={styles.itemText}>
        <div className={styles.icon} data-color={color.toLowerCase()}>
          {Icon ? <Icon /> : icon ? <Octicon icon={iconToPrimerIcon(icon)!} /> : null}
        </div>
        <span className={styles.truncatedItemText}>{title}</span>
      </div>
    </NavList.Item>
  )
}
