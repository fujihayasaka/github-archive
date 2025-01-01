import {Box, NavList} from '@primer/react'

import {LABELS} from '../../constants/labels'
import {useNavigationContext} from '../../contexts/NavigationContext'
import {ISSUES_INDEX_QUICK_FILTERS} from '../../constants/index-sidebar-constants'
import {SavedViewItem} from './SavedViewItem'
import {VALUES} from '../../constants/values'
import {VIEW_IDS} from '../../constants/view-constants'
import {CallToActionItem} from '../list/header/CallToActionItem'
import {QUERIES} from '@github-ui/query-builder/constants/queries'

export function IndexSidebar() {
  const {isNavigationOpen} = useNavigationContext()

  const linkItems = ISSUES_INDEX_QUICK_FILTERS.map((item, i) => {
    return (
      <SavedViewItem
        id={VIEW_IDS.repository}
        query={item.query}
        isTree={false}
        position={i}
        color={VALUES.defaultViewColor}
        key={item.name}
        title={item.name}
        icon={item.icon}
        defaultQuery={QUERIES.defaultRepoLevelOpen}
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
        minHeight: '100vh',
        px: isNavigationOpen ? 0 : 4,
        py: isNavigationOpen ? 0 : 3,
      }}
    >
      <NavList aria-label={LABELS.defaultViews} sx={{mb: 2, mx: -3}}>
        {linkItems}
      </NavList>
      <CallToActionItem optOutUrl={`/issues?new_issues_experience=false`} />
    </Box>
  )
}
