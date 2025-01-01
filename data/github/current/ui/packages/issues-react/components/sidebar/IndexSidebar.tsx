import {NavList} from '@primer/react'

import {LABELS} from '../../constants/labels'
import {useNavigationContext} from '../../contexts/NavigationContext'
import {ISSUES_INDEX_QUICK_FILTERS} from '../../constants/index-sidebar-constants'
import {SavedViewItem} from './SavedViewItem'
import {VALUES} from '../../constants/values'
import {VIEW_IDS} from '../../constants/view-constants'
import {QUERIES} from '@github-ui/query-builder/constants/queries'
import {CallToActionItem} from '../CallToActionItem'
import classes from './IndexSidebar.module.css'

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
        Icon={item.icon}
        defaultQuery={QUERIES.defaultRepoLevelOpen}
      />
    )
  })

  // If the mobile navigation dialog is open, this sidepanel is not a navigation landmark
  const role = isNavigationOpen ? undefined : 'navigation'

  return (
    <div
      role={role}
      className={classes.wrapper}
      aria-labelledby="sidebar-title"
      data-nav-open={isNavigationOpen ? 'true' : 'false'}
    >
      <NavList aria-label={LABELS.defaultViews} className={classes.list}>
        {linkItems}
      </NavList>
      <div className={classes.callToActionWrapper}>
        <CallToActionItem showBetaPill />
      </div>
    </div>
  )
}
