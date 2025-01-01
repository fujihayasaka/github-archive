import {http, HttpResponse} from 'msw'
import {setupWorker} from 'msw/browser'
import {beforeAll, afterEach} from './tests'
import {analyticsHandlers, resetAnalyticsEvents} from '@github-ui/analytics-test-utils/msw'

// Stub avatar-related alambic and githubusercontent requests
const avatarHandlers = [
  http.get('http://alambic.github.localhost/avatars/u/:userId', () => {
    return new HttpResponse(null, {status: 200})
  }),

  http.get('https://avatars.githubusercontent.com/u/:userId', () => {
    return new HttpResponse(null, {status: 200})
  }),
]

// Register global test handlers to start and reset MSW
beforeAll(async () => {
  await worker.start({quiet: false, onUnhandledRequest: 'warn'})

  return () => {
    worker.stop()
  }
})

afterEach(() => {
  resetAnalyticsEvents()
  worker.resetHandlers()
})

export const worker = setupWorker(...avatarHandlers, ...analyticsHandlers)
