import {Heading} from '@primer/react'
import {Links} from '../../components/Links'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {RoutePayload} from './types'

export function Training() {
  const routePayload = useRoutePayload<RoutePayload>()

  return (
    <>
      <Heading as="h1">Copilot is training based on your team’s data</Heading>
      <Links {...routePayload} />
    </>
  )
}
