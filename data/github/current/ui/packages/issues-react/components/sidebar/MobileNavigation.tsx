import {Dialog} from '@primer/react/experimental'
import type {PreloadedQuery} from 'react-relay'

import {LABELS} from '../../constants/labels'
import {useNavigationContext} from '../../contexts/NavigationContext'
import type {SavedViewsQuery} from './__generated__/SavedViewsQuery.graphql'
import {Sidebar} from './Sidebar'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from '../../types/app-payload'
import {IndexSidebar} from './IndexSidebar'

type MobileNavigationProps = {
  customViewsRef?: PreloadedQuery<SavedViewsQuery> | null
}

export default function MobileNavigation({customViewsRef}: MobileNavigationProps) {
  const {isNavigationOpen, closeNavigation} = useNavigationContext()
  const {scoped_repository} = useAppPayload<AppPayload>()

  return isNavigationOpen ? (
    <Dialog width="large" title={scoped_repository ? LABELS.quickFilters : LABELS.allViews} onClose={closeNavigation}>
      {scoped_repository ? <IndexSidebar /> : <Sidebar customViewsRef={customViewsRef} />}
    </Dialog>
  ) : null
}
