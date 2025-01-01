import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useNavigate} from '@github-ui/use-navigate'
import {Box, NavList, TreeView, useConfirm} from '@primer/react'
import {Octicon, Tooltip} from '@primer/react/deprecated'
import {useCallback, useTransition} from 'react'
import {Link} from 'react-router-dom'

import {LABELS} from '../../constants/labels'
import {useQueryContext, useQueryEditContext} from '../../contexts/QueryContext'
import {useNavigationContext} from '../../contexts/NavigationContext'
import {isQueryMatchSearchInUrl, searchUrl} from '../../utils/urls'
import {VIEW_COLOR_FOREGROUND_MAP} from './ColorHelper'
import {iconToPrimerIcon} from './IconHelper'
import {VIEW_IDS} from '../../constants/view-constants'

type Props = {
  id?: string
  icon: string
  color: string
  tooltip?: string
  title: string
  description?: string
  query?: string
  position: number
  isTree: boolean
  defaultQuery?: string
}

export function SavedViewItem({id, icon, color, tooltip, title, position, isTree, query, defaultQuery}: Props) {
  const {
    setViewPosition,
    setViewTeamId,
    setCanEditView,
    isNewView,
    setIsNewView,
    executeQuery,
    setIsQueryLoading,
    setCurrentPage,
  } = useQueryContext()
  const {dirtyDescription, dirtySearchQuery, setDirtySearchQuery, dirtyTitle, setDirtyDescription} =
    useQueryEditContext()
  const {closeNavigation} = useNavigationContext()

  const {pathname, search} = ssrSafeLocation
  const navigate = useNavigate()
  const confirm = useConfirm()
  const isCurrent = Boolean(pathname.endsWith(id ?? '') || isQueryMatchSearchInUrl({query, search, defaultQuery}))
  const url = searchUrl({viewId: id, query})
  const [, startTransition] = useTransition()

  const scopedRepoSubmitQuery = useCallback(async () => {
    if (!query || !executeQuery) return

    setDirtySearchQuery(query)
    setIsQueryLoading(true)
    startTransition(() => {
      executeQuery(query, 'store-or-network')
      setCurrentPage(1)
    })
    window.history.pushState(history.state, '', url)
  }, [executeQuery, query, setDirtySearchQuery, setIsQueryLoading, startTransition, setCurrentPage, url])

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
    <Box sx={{display: 'flex', flexDirection: 'row', gap: 2, alignItems: 'center'}}>
      <Octicon icon={iconToPrimerIcon(icon)!} sx={{color: VIEW_COLOR_FOREGROUND_MAP[color]}} />
      {tooltip ? <Tooltip aria-label={tooltip}>{title}</Tooltip> : title}
    </Box>
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
