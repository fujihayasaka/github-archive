import {beforeAll, afterEach} from './tests'
import {setupServer} from 'msw/node'

// Register global test handlers to start and reset MSW
beforeAll(async () => {
  server.listen()

  return () => {
    server.close()
  }
})

afterEach(() => {
  server.resetHandlers()
})

export const server = setupServer()
