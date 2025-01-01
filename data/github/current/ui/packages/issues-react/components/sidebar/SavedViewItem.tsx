import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useNavigate} from '@github-ui/use-navigate'
import {NavList, TreeView, useConfirm} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {useCallback} from 'react'
import {Link} from 'react-router-dom'

import {LABELS} from '../../constants/labels'
import {useQueryContext, useQueryEditContext} from '../../contexts/QueryContext'
import {useNavigationContext} from '../../contexts/NavigationContext'
import {isQueryMatchSearchInUrl, searchUrl} from '../../utils/urls'
import {iconToPrimerIcon} from './IconHelper'
import {VIEW_IDS} from '../../constants/view-constants'
import type {Icon} from '@primer/octicons-react'
import classes from './SavedViewItem.module.css'
import {useAppNavigate} from '../../hooks/use-app-navigate'

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
  isTree: boolean
  defaultQuery?: string
}

export function SavedViewItem({id, icon, Icon, color, title, position, isTree, query, defaultQuery}: Props) {
  const {setViewPosition, setViewTeamId, setCanEditView, isNewView, setIsNewView, setCurrentPage} = useQueryContext()
  const {dirtyDescription, dirtySearchQuery, dirtyTitle, setDirtyDescription} = useQueryEditContext()
  const {closeNavigation} = useNavigationContext()
  const {navigateToUrl} = useAppNavigate()

  const {pathname, search} = ssrSafeLocation
  const navigate = useNavigate()
  const confirm = useConfirm()
  const isCurrent = Boolean(pathname.endsWith(id ?? '') || isQueryMatchSearchInUrl({query, search, defaultQuery}))
  const url = searchUrl({viewId: id, query})

  const scopedRepoSubmitQuery = useCallback(async () => {
    navigateToUrl(url)
    setCurrentPage(1)
  }, [navigateToUrl, url, setCurrentPage])

  const submitQuery = useCallback(async () => {
    // In a repo's index, we don't want to navigate, just update the query
    // and update the UI
    if (id === VIEW_IDS.repository) {
      return scopedRepoSubmitQuery()
    }

    if (isNewView && (dirtyTitle !== LABELS.views.defaultName || dirtySearchQuery !== '' || dirtyDescription !== '')) {
      const discardChanges = await confirm({
        title: LABELS.views.unsavedChangesTitle,
        content: LABELS.views.unsavedChangesContent,
        confirmButtonType: 'danger',
      })
      if (!discardChanges) {
        return
      }
    }

    setIsNewView(false)
    navigate(url)
    setDirtyDescription('')
    setViewPosition(position)
    setViewTeamId(undefined)
    setCanEditView(true)
    closeNavigation()
  }, [
    id,
    scopedRepoSubmitQuery,
    isNewView,
    dirtyTitle,
    dirtySearchQuery,
    dirtyDescription,
    setIsNewView,
    navigate,
    url,
    setDirtyDescription,
    setViewPosition,
    position,
    setViewTeamId,
    setCanEditView,
    closeNavigation,
    confirm,
  ])

  const onSelect = useCallback(
    (event: React.MouseEvent | React.KeyboardEvent<HTMLElement>) => {
      submitQuery()
      event.preventDefault()
      event.stopPropagation()
    },
    [submitQuery],
  )
  // Slot cause problems with SSR since the component is rendered in a second pass
  // https://github.com/github/primer/issues/1224
  const itemText = (
    <div className={classes.itemText}>
      <div className={classes.icon} data-color={color.toLowerCase()}>
        {Icon ? <Icon /> : icon ? <Octicon icon={iconToPrimerIcon(icon)!} /> : null}
      </div>
      {title}
    </div>
  )

  return isTree ? (
    <TreeView.Item onSelect={onSelect} current={isCurrent} id={`${id}-shared-view-item`} data-testid="shared-view-item">
      {itemText}
    </TreeView.Item>
  ) : (
    <NavList.Item to={url} as={Link} aria-current={isCurrent ? 'page' : undefined} onClick={onSelect}>
      {itemText}
    </NavList.Item>
  )
}
