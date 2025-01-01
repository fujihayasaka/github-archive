import {MockAgentApi} from '../../__tests__/utilities/mock-agent-api'
import {MockAgentEventStream} from '../../__tests__/utilities/mock-agent-event-stream'

// Initialize the server but don't start it yet
MockAgentApi.getInstance().getServer().listen()

// Kludge alert! We cannot mock a streaming response in MSW
// See https://github.com/mswjs/msw/issues/1952
jest.spyOn(global, 'fetch').mockImplementation((url, ...args) => {
  if (url.toString().startsWith(`${MockAgentApi.BASE_URL}/events`)) {
    const stream = MockAgentEventStream.getInstance().getIterator()
    //@ts-expect-error - this is a mock response
    return new Response(stream, {
      status: 200,
      headers: {'Content-Type': 'text/event-stream'},
    })
  }

  // call the original fetch function
  const originalFetch = jest.requireActual('node-fetch')
  return originalFetch(url, ...args)
})

/**
 * Mock implementation of useFetchFromCodespaceApi hook
 * This returns a fetchFromCodespaceApi function that forwards requests to the MSW mock server
 */
function getFetchFromCodespaceApi() {
  const fetchFromCodespaceApi = async (path: string, init?: RequestInit): Promise<Response> => {
    // Normalize the path to ensure it starts with a slash
    const normalizedPath = path.startsWith('/') ? path : `/${path}`
    const url = `${MockAgentApi.BASE_URL}${normalizedPath}`

    // Forward the request to the MSW server with any headers from init
    return fetch(url, init)
  }

  return {fetchFromCodespaceApi}
}

// Alias for backward compatibility where the hook was expected
export const useFetchFromCodespaceApi = getFetchFromCodespaceApi
