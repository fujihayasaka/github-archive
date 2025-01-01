import {http, HttpResponse} from 'msw'

import {
  getReactCoreExamplesDependentDataDeferredPayload,
  getReactCoreExamplesDependentDataPayload,
  getReactCoreExamplesEnrichedDataDeferredPayload,
  getReactCoreExamplesEnrichedDataPayload,
  getReactCoreExamplesLayoutRoutePayload,
  getReactCoreExamplesLiveDataPayload,
  getReactCoreExamplesMutationsPayload,
  getReactCoreExamplesPaginationDeferredPayload,
  getReactCoreExamplesPaginationPayload,
  getReactCoreExamplesRoutePayload,
  getReactCoreExamplesSharedComponentsPayload,
} from './mock-data'

export const handlers = [
  http.get('https://avatars.githubusercontent.com/u/:id', async () => {
    return HttpResponse.arrayBuffer(await new Blob().arrayBuffer())
  }),

  http.get('/_react_core_examples', () => {
    const response = getReactCoreExamplesRoutePayload()
    return HttpResponse.json(response)
  }),

  http.get('/_react_core_examples/layout', () => {
    const response = getReactCoreExamplesLayoutRoutePayload()
    return HttpResponse.json(response)
  }),

  http.get('/_react_core_examples/dependent_data', () => {
    const response = getReactCoreExamplesDependentDataPayload()
    return HttpResponse.json(response)
  }),

  http.get('/_react_core_examples/dependent_data/deferred', () => {
    const response = getReactCoreExamplesDependentDataDeferredPayload()
    return HttpResponse.json(response)
  }),

  http.get('/_react_core_examples/enriched_data', () => {
    const response = getReactCoreExamplesEnrichedDataPayload()
    return HttpResponse.json(response)
  }),

  http.get('/_react_core_examples/enriched_data/deferred', () => {
    const response = getReactCoreExamplesEnrichedDataDeferredPayload()
    return HttpResponse.json(response)
  }),

  http.get('/_react_core_examples/live_data', () => {
    const response = getReactCoreExamplesLiveDataPayload()
    return HttpResponse.json(response)
  }),

  http.get('/_react_core_examples/mutations', () => {
    const response = getReactCoreExamplesMutationsPayload()
    return HttpResponse.json(response)
  }),

  http.get('/_react_core_examples/pagination', () => {
    const response = getReactCoreExamplesPaginationPayload()
    return HttpResponse.json(response)
  }),

  http.get('/_react_core_examples/pagination/deferred', () => {
    const response = getReactCoreExamplesPaginationDeferredPayload()
    return HttpResponse.json(response)
  }),

  http.get('/_react_core_examples/shared_components', () => {
    const response = getReactCoreExamplesSharedComponentsPayload()
    return HttpResponse.json(response)
  }),
]
