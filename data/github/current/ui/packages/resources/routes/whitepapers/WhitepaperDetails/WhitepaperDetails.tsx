import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

export interface WhitepaperDetailsPayload {
  // Update this type to reflect the data you place in payload in Rails
  text: string
}

export function WhitepaperDetails() {
  const payload = useRoutePayload<WhitepaperDetailsPayload>()
  return (
    <>
      <h1 data-hpc>Whitepaper Details</h1>
      <article>{JSON.stringify(payload)}</article>
    </>
  )
}
