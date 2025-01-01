import {IssuesLoadingSkeleton} from '@github-ui/issues-loading-skeleton'
import {Box, NavList} from '@primer/react'

import {LABELS} from '../../constants/labels'
import {VALUES} from '../../constants/values'
import useKnownViews from '../../hooks/use-known-views'
import {AppTitle} from './AppTitle'
import {iconToPrimerIcon} from './IconHelper'
import {SavedViewItem} from './SavedViewItem'
import {SidebarRow} from './SidebarRow'
import {CallToActionItem} from '../CallToActionItem'

export function SidebarLoading() {
  const {knownViews} = useKnownViews()

  const savedViewsItems = knownViews
    .filter(view => !view.hidden)
    .map((item, index) => {
      if (item.url) {
        return (
          <SidebarRow
            key={item.id}
            icon={iconToPrimerIcon(item.icon)!}
            id={item.id}
            path={item.url}
            title={item.name}
            tooltip=""
          />
        )
      }

      return (
        <SavedViewItem
          key={item.id}
          id={item.id}
          icon={item.icon}
          color={VALUES.defaultViewColor}
          title={item.name}
          query={item.query}
          position={index + 1}
        />
      )
    })

  return (
    <Box
      as="nav"
      aria-labelledby="sidebar-title"
      sx={{display: 'flex', flexDirection: 'column', minHeight: '100%', px: 4, py: 3}}
    >
      <div className="sr-only" aria-hidden="true">
        <AppTitle />
      </div>
      <NavList aria-label={LABELS.defaultViews} sx={{mb: 2, mx: -3}}>
        {savedViewsItems}
      </NavList>
      <NavList sx={{mx: -3}}>
        {[...Array(VALUES.viewLoadingSize)].map((_, index) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <NavList.Item key={index}>
            <NavList.LeadingVisual>
              <IssuesLoadingSkeleton borderRadius="elliptical" height="md" width="md" />
            </NavList.LeadingVisual>
            <IssuesLoadingSkeleton height="sm" width={'random'} />
          </NavList.Item>
        ))}
      </NavList>
      <Box sx={{mt: 'auto'}}>
        <Box sx={{mt: 4, borderTop: '1px solid', borderTopColor: 'border.muted', pt: 3}}>
          <CallToActionItem />
        </Box>
      </Box>
    </Box>
  )
}
