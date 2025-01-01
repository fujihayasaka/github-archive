import type {DefaultBodyType, HttpHandler} from 'msw'

import type {MswResponseResolver} from '../../../mocks/msw-responders'
import {mswServer} from '../../msw-server'

type RequestHandler<TRequest extends DefaultBodyType, TResponse> = (
  responseResolver: MswResponseResolver<TRequest, TResponse>,
) => HttpHandler

export function stubApiMethod<TRequest extends DefaultBodyType, TResponse>(
  requestHandler: RequestHandler<TRequest, TResponse>,
  resolvedRequest: TResponse,
) {
  const stub = jest.fn<TResponse, [TRequest]>()
  const handler = requestHandler(body => {
    stub(body)
    return Promise.resolve(resolvedRequest)
  })
  mswServer.use(handler)
  return stub
}

export function stubApiMethodForMultipleResponses<TRequest extends DefaultBodyType, TResponse>(
  requestHandler: RequestHandler<TRequest, TResponse>,
  resolvedRequests: Array<TResponse>,
) {
  let timesCalled = 0
  const stubs = resolvedRequests.map(() => jest.fn<TResponse, [TRequest]>())
  const handler = requestHandler(body => {
    const stub = stubs[timesCalled]
    const resolvedRequest = resolvedRequests[timesCalled]
    if (stub == null) {
      throw new Error('')
    }
    stub(body)
    timesCalled++
    return Promise.resolve(resolvedRequest)
  })
  mswServer.use(handler)
  return stubs
}

export function stubApiMethodWithError<TRequest extends DefaultBodyType, TResponse>(
  requestHandler: RequestHandler<TRequest, TResponse>,

  error: Error,
) {
  const stub = jest.fn<TResponse, [TRequest]>()

  const handler = requestHandler(body => {
    stub(body)

    return Promise.reject(error)
  })

  mswServer.use(handler)

  return stub
}
