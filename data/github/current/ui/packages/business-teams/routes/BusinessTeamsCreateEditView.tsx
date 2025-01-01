import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

export interface BusinessTeamsCreateEditPayload {
  // Update this type to reflect the data you place in payload in Rails
  someField: string
}

export function BusinessTeamsCreateEditView() {
  const payload = useRoutePayload<BusinessTeamsCreateEditPayload>()

  return (
    <>
      <h1 data-hpc>BusinessTeamsCreateEditView for business-teams</h1>
      <article>{payload.someField}</article>
    </>
  )
}
