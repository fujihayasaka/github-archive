//eslint-disable-next-line import/no-nodejs-modules -- we want to mock a fetch response with a ReadableStream
import {ReadableStream} from 'node:stream/web'

import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {AuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'

import {copilotFeatureFlags} from '../utils/copilot-feature-flags'

// eslint-disable-next-line compat/compat
window.requestIdleCallback = jest.fn()

jest.mocked(useAppPayload).mockReturnValue({
  copilotChatSettingEnabled: true,
  ssoOrganizations: [],
  apiURL: '', // This goes in front of all CAPI calls
})

// Staff-shipped flags
jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

beforeEach(() => {
  // Store auth token in local storage so that client doesn't try to fetch it
  const provider = new CopilotAuthTokenProvider([])
  provider.setLocalStorageAuthToken(new AuthToken('buttercakes', 'whenever', []))
})

// Copilot client uses regular fetch, as it doesn't hit the monolith and uses event streams
const mockFetch = jest.spyOn(global, 'fetch')

export class FetchDefinition {
  request: Request
  response?: unknown
  completed?: boolean
  error?: boolean
  constructor(request: Request, response: unknown, completed = false, error = false) {
    this.request = request
    this.response = response
    this.completed = completed
    this.error = error
  }
}

class Request {
  url: string
  method: string
  body?: unknown
  constructor(url: string, method: string, body?: unknown) {
    this.url = url
    this.method = method
    this.body = body
  }
}

// Mocks the fetch API to return the given responses
// onNonEmptyResponse is called when a non-empty response is returned to facilitate counting requests
export function mockResponses(fetches: FetchDefinition[], onNonEmptyResponse: () => void) {
  mockFetch.mockImplementation((url, options) => {
    for (const fetch of fetches) {
      const {request, response, completed} = fetch
      if (url === request.url && options?.method === request.method && !completed) {
        let payloadMatch = true
        // If expected body is a json object and response is not streaming match on partial request body
        if (typeof request.body === 'object') {
          const requestJson = request.body as Record<string, unknown>
          const optionsJson = JSON.parse(options.body as string) as Record<string, unknown>

          // Check that values provided in request match those in options
          for (const key in requestJson) {
            if (
              !requestJson[key] ||
              !optionsJson[key] ||
              // Deep compare each property
              JSON.stringify(requestJson[key]) !== JSON.stringify(optionsJson[key])
            ) {
              payloadMatch = false
            }
          }
        } else {
          if (options?.body !== request.body) {
            payloadMatch = false
          }
        }

        // If url and method matched, but payload didn't, try to find another fetch
        if (!payloadMatch) {
          continue
        }

        // Mark request as completed
        fetch.completed = true

        onNonEmptyResponse()

        // If we intend to return an error, return an empty response
        if (fetch.error) {
          return Promise.resolve({
            ok: false,
          } as Response)
        }

        // If response is an event stream, return a ReadableStream
        if (response instanceof EventStreamResponse) {
          return Promise.resolve(response as Response)
        }

        // Otherwise return a regular response
        return Promise.resolve({
          ok: true,
          json: () => response,
        } as Response)
      }
    }

    return Promise.resolve({
      ok: false,
    } as Response)
  })
}

// Object compatible with the Response object returned by fetch
class EventStreamResponse {
  body: {
    getReader: () => ReadableStreamDefaultReader<Uint8Array>
  }
  ok: boolean

  constructor(stream: ReadableStream<Uint8Array>) {
    this.body = {
      getReader: () => stream.getReader(),
    }
    this.ok = true
  }
}

// Creates a mock event stream response with a content and complete payload
export function mockEventStreamResponse(
  contentBody?: string,
  completePayload?: unknown,
  errorPayload?: unknown,
): EventStreamResponse {
  const encoder = new TextEncoder()
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      if (contentBody) {
        controller.enqueue(encoder.encode(`data: {"type":"content","body":"${contentBody}"}\n\n`))
      }

      if (errorPayload) {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(errorPayload)}\n\n`))
      }

      // Keep event stream open if complete or error payload is not provided
      // This is to simulate ongoing streaming
      if (!completePayload && !errorPayload) {
        return
      }

      if (completePayload) {
        ;(completePayload as Record<string, unknown>).type = 'complete'
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(completePayload)}\n\n`))
      }
      controller.close()
    },
  })

  return new EventStreamResponse(stream)
}
