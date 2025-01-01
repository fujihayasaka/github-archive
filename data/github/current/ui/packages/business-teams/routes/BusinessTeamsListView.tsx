import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

export interface BusinessTeamsListViewPayload {
  // Update this type to reflect the data you place in payload in Rails
  someField: string
}

export function BusinessTeamsListView() {
  const payload = useRoutePayload<BusinessTeamsListViewPayload>()

  return (
    <>
      <h1 data-hpc>BusinessTeamsListView for business-teams</h1>
      <article>{payload.someField}</article>
    </>
  )
}
