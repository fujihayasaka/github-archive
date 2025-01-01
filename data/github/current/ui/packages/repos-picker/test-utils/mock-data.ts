import {type DefaultBodyType, delay, http, HttpResponse, type StrictRequest} from 'msw'

import type {PickerRepository} from '../types'
import {buildRepo, sampleBillingRepos, sampleDefinitions, sampleRepos} from './test-helpers'

const definitionHandlers = {
  success: http.get(`/repositories/picker/definitions`, () => {
    return HttpResponse.json({definitions: sampleDefinitions})
  }),
  error: http.get(`/repositories/picker/definitions`, notFoundHandler),
  loading: http.get(`/repositories/picker/definitions`, infiniteDelayHandler),
}

const reposCountHandler = {
  success: http.get(`/repositories/picker/count`, () => {
    return HttpResponse.json({totalCount: sampleRepos.length})
  }),
  error: http.get(`/repositories/picker/count`, notFoundHandler),
  loading: http.get(`/repositories/picker/count`, infiniteDelayHandler),
}

const orgSuggestionsHandler = {
  success: http.get(`/enterprises/acme-corp/organizations/suggestions?org=&q=&filter_value=`, () =>
    HttpResponse.json({
      organizations: [
        {name: 'acme-org', login: 'acme-org', avatarUrl: 'https://avatars.githubusercontent.com/u/126255395?s=200&v=4'},
      ],
    }),
  ),
}

const numerousRepos = Array.from({length: 2345}, (_, i) => buildRepo(`repo-${i + 1}`, i + 100))

export const handlers = {
  success: [
    definitionHandlers.success,
    http.get(`/repositories/picker/search`, getReposHandler(sampleRepos)),
    reposCountHandler.success,
    orgSuggestionsHandler.success,
  ],
  successForBilling: [
    definitionHandlers.success,
    http.get(`/billing/repos-search`, getReposHandler(sampleBillingRepos)),
    reposCountHandler.success,
    orgSuggestionsHandler.success,
  ],
  numerousRepos: [
    definitionHandlers.success,
    http.get(`/repositories/picker/search`, getReposHandler(numerousRepos)),
    reposCountHandler.success,
    orgSuggestionsHandler.success,
  ],
  error: [definitionHandlers.error, http.get(`/repositories/picker/search`, notFoundHandler), reposCountHandler.error],
  loading: [
    definitionHandlers,
    http.get(`/repositories/picker/search`, infiniteDelayHandler),
    reposCountHandler.loading,
  ],
}

function getReposHandler(allRepos: PickerRepository[]) {
  return ({request}: {request: StrictRequest<DefaultBodyType>}) => {
    const url = new URL(request.url, window.location.origin)
    const q = url.searchParams.get('q')
    const repos = q ? allRepos.filter(repo => repo.name.includes(q)) : allRepos
    return HttpResponse.json({items: repos.slice(0, 100), totalCount: repos.length})
  }
}

function notFoundHandler() {
  return new HttpResponse('Not found', {status: 404})
}

function infiniteDelayHandler() {
  return delay('infinite')
}
