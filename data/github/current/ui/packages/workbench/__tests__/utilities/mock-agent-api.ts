import {http, HttpResponse} from 'msw'
import type {SetupServerApi} from 'msw/node'
import {setupServer} from 'msw/node'

type EndpointConfig = {
  statusCode?: number
  response?: Record<string, unknown>
  delay?: number
}

type EventsEndpointConfig = {
  mockEventStream?: ReadableStream
  statusCode?: number
  delay?: number
}

type EndpointsConfig = {
  events?: EventsEndpointConfig
  iterate?: EndpointConfig
  cancel?: EndpointConfig
  publish?: EndpointConfig
}

// Dynamic updatable configuration for the mock server
interface MockAgentServer extends SetupServerApi {
  mockEvents(config: EventsEndpointConfig): void
  mockIterate(config: EndpointConfig): void
  mockCancel(config: EndpointConfig): void
  mockPublish(config: EndpointConfig): void
  resetMockConfig(): void
}

export class MockAgentApi {
  private static instance: MockAgentApi | null = null
  private server: MockAgentServer
  private mutableConfig: EndpointsConfig

  public static BASE_URL = 'https://cmackie-waz-here-9000.puckerman.the.cat'

  private constructor(config: EndpointsConfig = {}) {
    this.mutableConfig = {...config}
    this.server = setupServer(...this.createHandlers()) as MockAgentServer

    // Add methods to dynamically update the config
    this.server.mockEvents = this.mockEvents.bind(this)
    this.server.mockIterate = this.mockIterate.bind(this)
    this.server.mockCancel = this.mockCancel.bind(this)
    this.server.mockPublish = this.mockPublish.bind(this)
    this.server.resetMockConfig = this.resetMockConfig.bind(this)
  }

  /**
   * Get singleton instance of MockAgentApi
   */
  public static getInstance(config?: EndpointsConfig): MockAgentApi {
    if (!MockAgentApi.instance) {
      MockAgentApi.instance = new MockAgentApi(config)
    }
    return MockAgentApi.instance
  }

  /**
   * Reset the singleton instance
   */
  public static resetInstance(): void {
    if (MockAgentApi.instance) {
      MockAgentApi.instance.server.close()
      MockAgentApi.instance = null
    }
  }

  /**
   * Get the server instance
   */
  public getServer(): MockAgentServer {
    return this.server
  }

  public mockEvents(eventsConfig: EventsEndpointConfig): void {
    this.mutableConfig = {...this.mutableConfig, events: eventsConfig}
    this.server.resetHandlers(...this.createHandlers())
  }

  public mockIterate(iterateConfig: EndpointConfig): void {
    this.mutableConfig = {...this.mutableConfig, iterate: iterateConfig}
    this.server.resetHandlers(...this.createHandlers())
  }

  public mockCancel(cancelConfig: EndpointConfig): void {
    this.mutableConfig = {...this.mutableConfig, cancel: cancelConfig}
    this.server.resetHandlers(...this.createHandlers())
  }

  public mockPublish(publishConfig: EndpointConfig): void {
    this.mutableConfig = {...this.mutableConfig, publish: publishConfig}
    this.server.resetHandlers(...this.createHandlers())
  }

  public resetMockConfig(): void {
    this.mutableConfig = {}
    this.server.resetHandlers(...this.createHandlers())
  }

  private createHandlers() {
    return [
      // Events stream endpoint
      http.get(`${MockAgentApi.BASE_URL}/events`, async () => {
        throw new Error(
          'Since this returns a stream, it cannot be mocked with msw while we use jest. See https://github.com/mswjs/msw/issues/1952',
        )
      }),

      // Iterate endpoint
      http.post(`${MockAgentApi.BASE_URL}/iterate`, async () => {
        const {iterate} = this.mutableConfig

        if (iterate?.statusCode && iterate.statusCode >= 400) {
          return new HttpResponse(JSON.stringify({error: `Error ${iterate.statusCode}`}), {
            status: iterate.statusCode,
            headers: {'Content-Type': 'application/json'},
          })
        }

        return new HttpResponse(JSON.stringify(iterate?.response || {success: true}), {
          status: 200,
          headers: {'Content-Type': 'application/json'},
        })
      }),

      // Cancel endpoint
      http.post(`${MockAgentApi.BASE_URL}/cancel`, async () => {
        const {cancel} = this.mutableConfig

        if (cancel?.statusCode && cancel.statusCode >= 400) {
          return new HttpResponse(JSON.stringify({error: `Error ${cancel.statusCode}`}), {
            status: cancel.statusCode,
            headers: {'Content-Type': 'application/json'},
          })
        }

        return new HttpResponse(JSON.stringify(cancel?.response || {success: true}), {
          status: 200,
          headers: {'Content-Type': 'application/json'},
        })
      }),

      // Publish endpoint
      http.post(`${MockAgentApi.BASE_URL}/publish`, async () => {
        const {publish} = this.mutableConfig

        if (publish?.statusCode && publish.statusCode >= 400) {
          return new HttpResponse(JSON.stringify({error: `Error ${publish.statusCode}`}), {
            status: publish.statusCode,
            headers: {'Content-Type': 'application/json'},
          })
        }

        return new HttpResponse(
          JSON.stringify(publish?.response || {repository: {url: 'https://github.com/user/repo'}}),
          {
            status: 200,
            headers: {'Content-Type': 'application/json'},
          },
        )
      }),
    ]
  }
}
