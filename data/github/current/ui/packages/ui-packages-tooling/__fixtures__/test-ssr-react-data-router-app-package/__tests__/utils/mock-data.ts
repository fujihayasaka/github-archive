import type {SomeRouteResponse} from '../../routes/some-route-route'

export function getSomeRouteRoutePayload(): SomeRouteResponse {
  return {
    someField: 'someValue',
  }
}
