import {http, HttpResponse} from '@github-ui/tests/msw'
import {someRouteRoute} from '../../routes/some-route-route'
import {getSomeRouteRoutePayload} from './mock-data'

export const handlers = [
  http.get(someRouteRoute.path, () => {
    const response = getSomeRouteRoutePayload()
    return HttpResponse.json({
      payload: {
        [someRouteRoute.id]: response,
      },
    })
  }),
]
