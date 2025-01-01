import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

export interface BusinessTeamsItemViewPayload {
  // Update this type to reflect the data you place in payload in Rails
  someField: string
}

export function BusinessTeamsItemView() {
  const payload = useRoutePayload<BusinessTeamsItemViewPayload>()

  return (
    <>
      <h1 data-hpc>BusinessTeamsItemView for business-teams</h1>
      <article>{payload.someField}</article>
    </>
  )
}
