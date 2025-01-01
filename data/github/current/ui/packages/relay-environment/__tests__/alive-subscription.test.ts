import {subscribe} from '../alive-subscription'
import type {RequestParameters} from 'relay-runtime'
import {mockFetch} from '@github-ui/mock-fetch'

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest
    .fn()
    .mockImplementation((featureName: string) => featureName === 'allow_subscription_halted_error'),
}))

const getDefaultParams = (id: string): RequestParameters => ({
  name: 'TestQuery',
  text: null,
  id,
  operationKind: 'query',
  metadata: {
    isRelayRouteRequest: true,
  },
  providedVariables: {},
})

const URL: RegExp = /.*/

describe('subscribe', () => {
  beforeEach(() => {
    process.env.APP_ENV = 'test'
    mockFetch.clear()
  })

  it('should return a subscription', () => {
    const subscription = subscribe(getDefaultParams('1'), () => {})
    expect(subscription).toBeDefined()
  })

  it('should not throw an error when fetchGraphQLWithSubscription returns successfully', async () => {
    const mockData = {
      data: {
        happy: true,
      },
    }
    const options = {
      headers: new Headers({'Content-Type': 'application/json'}),
      ok: true,
      status: 200,
    }
    mockFetch.mockRouteOnce(URL, mockData, options)

    const subscription = subscribe(getDefaultParams('2'), () => {})
    await subscription.subscribe({
      next: () => {},
      error: () => {},
      complete: () => {},
    })
    expect(subscription).toBeDefined()
  })

  // I would like to test other errors here but because we're calling `subscribeToAlive()` without `async`
  // we can't catch the error
  it('should not throw an error when fetchGraphQLWithSubscription returns "subscription halted"', async () => {
    const mockData = {
      errors: [
        {
          type: 'TEST',
          path: ['testError'],
          message: 'Subscription halted',
        },
      ],
    }
    const options = {
      headers: new Headers({'Content-Type': 'application/json'}),
      ok: true,
      status: 200,
    }
    mockFetch.mockRouteOnce(URL, mockData, options)

    const subscription = subscribe(getDefaultParams('3'), () => {})
    await subscription.subscribe({
      next: () => {},
      error: () => {},
      complete: () => {},
    })
    expect(subscription).toBeDefined()
  })
})
