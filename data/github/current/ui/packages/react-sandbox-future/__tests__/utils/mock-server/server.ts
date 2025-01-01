import {setupServer as setupMSWServer} from 'msw/node'

import {handlers} from './handlers'

export function setupServer() {
  const server = setupMSWServer(...handlers)

  beforeAll(() => server.listen())
  afterEach(() => {
    server.resetHandlers()
  })
  afterAll(() => server.close())

  return {server}
}
