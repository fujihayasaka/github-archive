import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {ShowApp as LegacyShowApp} from '../components/legacy/ShowApp'
import {ListingLayout} from '../components/ListingLayout'
import type {ShowAppPayload} from '../types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

export function ShowApp() {
  const redesignFeatureFlag = useFeatureFlag('marketplace_layout_redesign')

  return <>{redesignFeatureFlag ? <RedesignedShowApp /> : <LegacyShowApp />}</>
}

const RedesignedShowApp = () => {
  const {listing} = useRoutePayload<ShowAppPayload>()
  return <ListingLayout header="Header" body={<div>Body</div>} sidebar={<div>Sidebar</div>} listing={listing} />
}
