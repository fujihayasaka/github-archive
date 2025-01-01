import {http, HttpResponse} from 'msw'

import {
  getReactSandBoxDashboardDeferredPayload,
  getReactSandBoxDashboardDiscussionsPayload,
  getReactSandBoxDashboardIssuesDeferredIssuesPayload,
  getReactSandBoxDashboardIssuesPayload,
  getReactSandBoxDashboardPayload,
  getReactSandboxDeferredPayload,
  getReactSandboxFutureIdRoutePayload,
  getReactSandboxFutureIndexRoutePayload,
  getReactSandboxLayoutRoutePayload,
} from '../mock-data'

export const handlers = [
  http.get('/_react_sandbox_future/_layout', () => {
    const response = getReactSandboxLayoutRoutePayload()
    return HttpResponse.json(response)
  }),

  http.get('/_react_sandbox_future', () => {
    const response = getReactSandboxFutureIndexRoutePayload(true)
    return HttpResponse.json(response)
  }),

  http.get('/_react_sandbox_future/dashboard', () => {
    const response = getReactSandBoxDashboardPayload()
    return HttpResponse.json(response)
  }),

  http.get('/_react_sandbox_future/3', () => {
    return new HttpResponse('Page not found', {status: 404})
  }),

  http.get('/_react_sandbox_future/:id', ({params}) => {
    const {id} = params
    const response = getReactSandboxFutureIdRoutePayload(id as string, true)
    return HttpResponse.json(response)
  }),

  http.get('/_react_sandbox_future/dashboard/deferred', () => {
    const response = getReactSandBoxDashboardDeferredPayload({openIssues: 2, openPulls: 2})
    return HttpResponse.json(response)
  }),

  http.get('/_react_sandbox_future/:id/deferred', ({params}) => {
    const {id} = params
    const response = getReactSandboxDeferredPayload(id as string)
    return HttpResponse.json(response)
  }),

  http.get('/_react_sandbox_future/dashboard/issues', ({request}) => {
    const searchParams = new URL(request.url, window.location.origin).searchParams
    const state = (searchParams.get('state') || 'open') as 'open' | 'closed'
    const response = getReactSandBoxDashboardIssuesPayload({state, count: {open: 2, closed: 2}}, true)
    return HttpResponse.json(response)
  }),

  http.get('/_react_sandbox_future/dashboard/issues/deferred', ({request}) => {
    const searchParams = new URL(request.url, window.location.origin).searchParams
    const state = (searchParams.get('state') || 'open') as 'open' | 'closed'
    const response = getReactSandBoxDashboardIssuesDeferredIssuesPayload({state, count: {open: 2, closed: 2}})
    return HttpResponse.json(response)
  }),

  http.get('/_react_sandbox_future/dashboard/discussions', () => {
    const response = getReactSandBoxDashboardDiscussionsPayload({open: 2, closed: 2}, true)
    return HttpResponse.json(response)
  }),
]
