import {mockClientEnv} from '@github-ui/client-env/mock'
import {sendEvent} from '../utils/send-event'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {sendEvent as hydroSendEvent} from '@github-ui/hydro-analytics'

jest.mock('@github-ui/hydro-analytics', () => ({
  sendEvent: jest.fn().mockName('sendEvent'),
  currentCatalogService: () => 'catalog-service',
}))

const hydroSendEventMocked = jest.mocked(hydroSendEvent)

beforeEach(() => {
  jest.resetAllMocks()
})

describe('sendEvent', () => {
  it('calls out to hydro-analytics synchronously when not under any feature flag', () => {
    expect(isFeatureEnabled('github_models_scheduled_hydro_events')).toBe(false)

    sendEvent('test-event', {test: 'data'})
    expect(hydroSendEventMocked).toHaveBeenCalledWith('test-event', {test: 'data'})
  })

  it('schedules the hydro-analytics call when under the feature flag', async () => {
    mockClientEnv({featureFlags: ['github_models_scheduled_hydro_events']})
    expect(isFeatureEnabled('github_models_scheduled_hydro_events')).toBe(true)

    jest.useFakeTimers()

    sendEvent('test-event', {test: 'data'})

    expect(hydroSendEventMocked).toHaveBeenCalledTimes(0)

    await jest.runAllTimersAsync()

    expect(hydroSendEventMocked).toHaveBeenCalledWith('test-event', {
      service: 'catalog-service',
      test: 'data',
    })
  })
})
