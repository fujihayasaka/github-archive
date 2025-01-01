import {ListingLayout} from '../components/ListingLayout'
import {Header} from '../components/apps/Header'
import {Body} from '../components/apps/Body'
import {Sidebar} from '../components/apps/Sidebar'
import type {ShowAppPayload} from '../types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

export function ShowApp() {
  const {listing, planInfo, userCanEdit, screenshots, supportedLanguages, permissionsData} =
    useRoutePayload<ShowAppPayload>()

  return (
    <ListingLayout
      header={<Header app={listing} planInfo={planInfo} userCanEdit={userCanEdit} />}
      body={
        <Body
          app={listing}
          screenshots={screenshots}
          planInfo={planInfo}
          supportedLanguages={supportedLanguages}
          permissionsData={permissionsData}
        />
      }
      sidebar={<Sidebar app={listing} planInfo={planInfo} supportedLanguages={supportedLanguages} />}
    />
  )
}
