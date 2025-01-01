import {expect, test} from '@jest/globals'
import {CompletionApi} from '../completion-api'
import {sendEvent} from '@github-ui/hydro-analytics'

jest.mock('@github-ui/hydro-analytics', () => ({
  sendEvent: jest.fn(),
}))

describe('CompletionApi', () => {
  describe('complete', () => {
    afterEach(() => {
      jest.restoreAllMocks()
    })

    test('uses Proxy to fetch a completion', async () => {
      const api = new CompletionApi()
      api.completionsUrl = '/mock-completions'
      jest.spyOn(api, 'refreshProxyToken').mockResolvedValue(undefined)

      const fetchSpy = jest.spyOn(global, 'fetch')
      fetchSpy.mockResolvedValue({
        status: 200,
      } as Response)

      await api.complete('prompt', 'suffix', new AbortController().signal, true)

      expect(fetchSpy).toHaveBeenCalledTimes(1)
    })

    test('falls back to dotcom if Proxy returns multiple 422s', async () => {
      const api = new CompletionApi()
      jest.spyOn(api, 'refreshProxyToken').mockResolvedValue(undefined)
      const fetchSpy = jest.spyOn(global, 'fetch')
      fetchSpy.mockResolvedValue({
        status: 422,
      } as Response)

      await api.complete('prompt', 'suffix', new AbortController().signal, true)

      expect(fetchSpy).toHaveBeenNthCalledWith(1, api.completionsUrl, expect.anything())
      expect(fetchSpy).toHaveBeenNthCalledWith(2, api.completionsUrl, expect.anything())
      expect(fetchSpy).toHaveBeenNthCalledWith(3, '/copilot/completions', expect.anything())
    })

    test('emits to telemetry when we fail to make a request', async () => {
      const api = new CompletionApi()
      jest.spyOn(api, 'refreshProxyToken').mockResolvedValue(undefined)
      jest.spyOn(global, 'fetch').mockRejectedValue(new Error('CSP Error'))
      jest.mock('@github-ui/hydro-analytics', () => {
        return {
          ...jest.requireActual('@github-ui/hydro-analytics'),
          sendEvent: jest.fn(),
        }
      })

      let cspError = null as Error | null
      try {
        await api.complete('prompt', 'suffix', new AbortController().signal, true)
      } catch (error) {
        cspError = error as Error
      }
      expect(cspError).toBeInstanceOf(Error)
      expect(cspError?.message).toEqual('CSP Error')
      expect((sendEvent as jest.Mock).mock.calls).toContainEqual([
        'ghost-pilot.completion-not-ok',
        {error: 'Error: CSP Error', target: 'proxy', version: '0.0.0'},
      ])
    })

    test('handles a multi-chunk stream response that splits data', async () => {
      const api = new CompletionApi()
      jest.spyOn(api, 'refreshProxyToken').mockResolvedValue(undefined)
      const fetchSpy = jest.spyOn(global, 'fetch')
      fetchSpy.mockResolvedValue({
        status: 200,
        body: {
          getReader() {
            return {
              read() {
                // Ultimately ignored by mocked TextDecoder, we just don't want it to finish early with `done: true`.
                return {done: false, value: new Uint8Array([1, 2, 3])}
              },
            }
          },
        },
      } as unknown as Response)
      // JSON objects are cut-off between chunks, and include more than one to stress-test the string replacing logic.
      const textDecoderSpy = jest
        .spyOn(window.TextDecoder.prototype, 'decode')
        .mockImplementationOnce(() => 'data: {"id":"foo","model":"gpt-35-turbo","choices":[{"text')
        .mockImplementationOnce(() => '":".","logprobs":{"tokens":["."],"token_logprobs":[-1.0],"top_logprobs":[]}}]}')
        .mockImplementationOnce(() => '\n\ndata: {"id":"foo","model":"gpt-35-turbo","choices":[{"text')
        .mockImplementationOnce(() => '":".","logprobs":{"tokens":["."],"token_logprobs":[-1.0],"top_logprobs":[]}}]}')
        .mockImplementationOnce(() => '\n\ndata: [DONE]\n\n')

      await api.complete('prompt', 'suffix', new AbortController().signal, true)

      expect(fetchSpy).toHaveBeenCalledTimes(1)
      expect(textDecoderSpy).toHaveBeenCalledTimes(5)
    })

    test('user angent to match controller regex', async () => {
      const api = new CompletionApi()
      // This RegExp is defined inside GhostPilot::CompletionsController
      const match = api.userAgent.match(/^GitHub(GhostPilot|WorkspaceEditor)\/[\\.\d]+$/)
      expect(match).not.toBeNull()
    })
  })
})
