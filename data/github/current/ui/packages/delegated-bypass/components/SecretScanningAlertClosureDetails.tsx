import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {SearchIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import type {ExemptionRequestPayload, NewExemptionRequestPayload} from '../delegated-bypass-types'
import {useRelativeNavigation} from '../hooks/use-relative-navigation'

export function SecretScanningAlertClosureDetails() {
  const titleText = 'Secret scanning alert link'
  const payload = useRoutePayload<ExemptionRequestPayload | NewExemptionRequestPayload>()
  let resourceId = null
  if ('resourceId' in payload && payload.resourceId) {
    resourceId = payload.resourceId
  } else if ('request' in payload && payload.request.resourceId) {
    resourceId = payload.request.resourceId
  }
  const {resolvePath} = useRelativeNavigation()

  return (
    <div className="mx-4 py-3">
      <div className="flex-justify-center ">
        <div className="flex-items-center ">
          <SearchIcon size={16} />
          {resourceId && (
            <Link className="ml-2" href={resolvePath(`../../../security/secret-scanning/${resourceId}`)}>
              {titleText}
            </Link>
          )}
        </div>
      </div>
    </div>
  )
}
