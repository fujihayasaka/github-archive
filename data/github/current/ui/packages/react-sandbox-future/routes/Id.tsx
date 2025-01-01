import {useRouteParams} from '@github-ui/react-core/future/use-route-params'

import {DisplayQueries} from '../components/DisplayQueries'
import {FooterLinks} from '../components/FooterLinks'
import {SpaceFiller} from '../components/SpaceFiller'
import {reactSandboxFutureIdRoute} from './id-route'

export function ReactSandboxFutureId() {
  const {id} = useRouteParams(reactSandboxFutureIdRoute)

  return (
    <>
      <h2 data-hpc>{`ReactSandboxFutureId: id=${id}`}</h2>
      <DisplayQueries route={reactSandboxFutureIdRoute} />

      <SpaceFiller />

      <FooterLinks />
    </>
  )
}
