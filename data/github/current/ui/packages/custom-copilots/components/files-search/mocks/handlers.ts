// eslint-disable-next-line import/no-extraneous-dependencies
import {http, HttpResponse} from 'msw'

export const handlers = [
  http.get('/owner/test-repo/tree-list/:commitOid', () => {
    return HttpResponse.json({
      paths: ['contra', 'transport', 'ter/rain', '/src'],
    })
  }),
]
