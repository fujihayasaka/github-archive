import {Box, NavList} from '@primer/react'
import {Suspense, useMemo} from 'react'
import type {PreloadedQuery} from 'react-relay/hooks'

import {LABELS} from '../../constants/labels'
import {VALUES} from '../../constants/values'
import {useNavigationContext} from '../../contexts/NavigationContext'
import useKnownViews from '../../hooks/use-known-views'
import {useViewsNav} from '../../hooks/viewsNav'
import type {SavedViewsQuery} from './__generated__/SavedViewsQuery.graphql'
import {AppTitle} from './AppTitle'
import {iconToPrimerIcon} from './IconHelper'
import {SavedViewItem} from './SavedViewItem'
import {SavedViews} from './SavedViews'
import {SidebarLoading} from './SidebarLoading'
import {SidebarRow} from './SidebarRow'
import {CallToActionItem} from '../CallToActionItem'

type SidebarProps = {
  customViewsRef: PreloadedQuery<SavedViewsQuery> | undefined | null
  isFullHeight?: boolean
}

export const Sidebar = ({customViewsRef, isFullHeight}: SidebarProps) => {
  if (!customViewsRef) return <SidebarLoading />
  return (
    <Suspense fallback={<SidebarLoading />}>
      <SidebarInternal customViewsRef={customViewsRef} isFullHeight={isFullHeight} />
    </Suspense>
  )
}

type SidebarInternalProps = {
  customViewsRef: PreloadedQuery<SavedViewsQuery>
  isFullHeight?: boolean
}

function SidebarInternal({customViewsRef, isFullHeight}: SidebarInternalProps) {
  const {knownViews, knownViewRoutes} = useKnownViews()
  const {isNavigationOpen} = useNavigationContext()

  const viewKeys = useMemo(() => knownViews.map((_item, index) => (index + 1).toString()), [knownViews])
  useViewsNav(knownViewRoutes, viewKeys)

  const savedViewItems = knownViews
    .filter(view => !view.hidden)
    .map((item, index) => {
      if (item.url) {
        return (
          <SidebarRow
            key={item.id}
            title={item.name}
            icon={iconToPrimerIcon(item.icon)!}
            id={item.id}
            path={item.url}
            tooltip={item.name}
          />
        )
      }

      return (
        <SavedViewItem
          key={item.id}
          id={item.id}
          position={index + 1}
          icon={item.icon}
          color={VALUES.defaultViewColor}
          title={item.name}
        />
      )
    })

  return (
    <Box
      as={isNavigationOpen ? 'div' : 'nav'}
      aria-labelledby="sidebar-title"
      sx={{
        display: 'flex',
        flexDirection: 'column',
        px: 4,
        py: 3,
        height: isFullHeight ? 'calc(100vh - 64px)' : 'auto',
      }}
    >
      <div className="sr-only" aria-hidden="true">
        <AppTitle />
      </div>
      <NavList aria-label={LABELS.defaultViews} sx={{mb: 2, mx: -3}}>
        {savedViewItems}
      </NavList>
      <SavedViews savedViewsRef={customViewsRef} />
      <Box sx={{mt: 'auto'}}>
        <CallToActionItem />
      </Box>
    </Box>
  )
}
