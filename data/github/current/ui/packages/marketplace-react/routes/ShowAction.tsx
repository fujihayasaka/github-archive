import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ListingLayout} from '../components/ListingLayout'
import {Header} from '../components/actions/Header'
import {Body} from '../components/actions/Body'
import {Sidebar} from '../components/actions/Sidebar'
import type {ShowActionPayload} from '../types'

export function ShowAction() {
  const payload = useRoutePayload<ShowActionPayload>()
  const {action, readmeHtml, helpUrl, repository, delistActionData} = payload

  return (
    <ListingLayout
      header={<Header action={action} repository={repository} delistActionData={delistActionData} />}
      body={<Body readmeHtml={readmeHtml} helpUrl={helpUrl} repository={repository} action={action} />}
      listing={action}
      sidebar={<Sidebar action={action} repository={repository} />}
    />
  )
}
