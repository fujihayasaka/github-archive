import {type DefaultBodyType, delay, http, HttpResponse, type StrictRequest} from 'msw'

import type {PickerRepository} from '../types'
import {buildRepo, sampleDefinitions, sampleRepos} from './test-helpers'

const definitionHandlers = {
  success: http.get(`/repos-picker/definitions`, () => {
    return HttpResponse.json({definitions: sampleDefinitions})
  }),
  error: http.get(`/repos-picker/definitions`, notFoundHandler),
  loading: http.get(`/repos-picker/definitions`, infiniteDelayHandler),
}

const numerousRepos = Array.from({length: 2345}, (_, i) => buildRepo(`repo-${i + 1}`, i + 100))

export const handlers = {
  success: [definitionHandlers.success, http.get(`/repos-picker/repositories`, getReposHandler(sampleRepos))],
  numerousRepos: [definitionHandlers.success, http.get(`/repos-picker/repositories`, getReposHandler(numerousRepos))],
  error: [definitionHandlers.error, http.get(`/repos-picker/repositories`, notFoundHandler)],
  loading: [definitionHandlers, http.get(`/repos-picker/repositories`, infiniteDelayHandler)],
}

function getReposHandler(allRepos: PickerRepository[]) {
  return ({request}: {request: StrictRequest<DefaultBodyType>}) => {
    const url = new URL(request.url, window.location.origin)
    const q = url.searchParams.get('q')
    const repos = q ? allRepos.filter(repo => repo.name.includes(q)) : allRepos
    return HttpResponse.json({repositories: repos.slice(0, 100), repositoryCount: repos.length})
  }
}

function notFoundHandler() {
  return new HttpResponse('Not found', {status: 404})
}

function infiniteDelayHandler() {
  return delay('infinite')
}
