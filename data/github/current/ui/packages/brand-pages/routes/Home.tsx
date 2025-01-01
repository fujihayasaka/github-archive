import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

export interface HomePayload {
  // Update this type to reflect the data you place in payload in Rails
  someField: string
}

export function Home() {
  const payload = useRoutePayload<HomePayload>()

  return (
    <>
      <h1 data-hpc>Home for brand-pages</h1>
      <article>{payload.someField}</article>
    </>
  )
}
