import type {HomePayload} from '../routes/Home'

export function getHomeRoutePayload(): HomePayload {
  return {
    someField: 'Payload for the brand-pages Home route',
  }
}
