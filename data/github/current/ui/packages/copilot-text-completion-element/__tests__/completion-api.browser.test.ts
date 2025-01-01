import {afterEach, beforeEach, describe, expect, it, vi, type Mock} from '@github-ui/tests'
import {CompletionApi} from '../completion-api'
import {featureFlag} from '@github-ui/feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'

vi.mock('@github-ui/hydro-analytics', async importOriginal => {
  return {
    ...(await importOriginal()),
    sendEvent: vi.fn(),
  }
})

vi.mock('@github-ui/feature-flags')

describe('CompletionApi', () => {
  describe('complete', () => {
    beforeEach(() => {
      vi.mocked(featureFlag.isFeatureEnabled).mockReturnValue(false)
    })

    afterEach(() => {
      vi.restoreAllMocks()
    })

    it('uses Proxy to fetch a completion', async () => {
      const api = new CompletionApi()
      api.completionsUrl = '/mock-completions'
      vi.spyOn(api, 'refreshProxyToken').mockResolvedValue(undefined)

      const fetchSpy = vi.spyOn(globalThis, 'fetch')
      fetchSpy.mockResolvedValue({
        status: 200,
      } as Response)

      await api.complete('prompt', 'suffix', new AbortController().signal, true)

      expect(fetchSpy).toHaveBeenCalledTimes(1)
    })

    it.skip('falls back to dotcom if Proxy returns multiple 422s', async () => {
      vi.mocked(featureFlag.isFeatureEnabled).mockReturnValue(true)
      const api = new CompletionApi()
      vi.spyOn(api, 'refreshProxyToken').mockResolvedValue(undefined)
      const fetchSpy = vi.spyOn(globalThis, 'fetch')
      fetchSpy.mockResolvedValue({
        status: 422,
      } as Response)

      await api.complete('prompt', 'suffix', new AbortController().signal, true)

      expect(fetchSpy).toHaveBeenNthCalledWith(1, api.completionsUrl, expect.anything())
      expect(fetchSpy).toHaveBeenNthCalledWith(2, api.completionsUrl, expect.anything())
      expect(fetchSpy).toHaveBeenNthCalledWith(3, '/copilot/completions', expect.anything())
    })

    it('emits to telemetry when we fail to make a request', async () => {
      const api = new CompletionApi()
      vi.spyOn(api, 'refreshProxyToken').mockResolvedValue(undefined)
      vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('CSP Error'))

      let cspError = null as Error | null
      try {
        await api.complete('prompt', 'suffix', new AbortController().signal, true)
      } catch (error) {
        cspError = error as Error
      }
      expect(cspError).toBeInstanceOf(Error)
      expect(cspError?.message).toEqual('CSP Error')
      expect((sendEvent as Mock).mock.calls).toContainEqual([
        'ghost-pilot.completion-not-ok',
        {error: 'Error: CSP Error', target: 'proxy', version: '0.0.0'},
      ])
    })

    it('handles a multi-chunk stream response that splits data', async () => {
      const api = new CompletionApi()
      vi.spyOn(api, 'refreshProxyToken').mockResolvedValue(undefined)
      const fetchSpy = vi.spyOn(globalThis, 'fetch')
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
      const textDecoderSpy = vi
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

    it('user angent to match controller regex', async () => {
      const api = new CompletionApi()
      // This RegExp is defined inside GhostPilot::CompletionsController
      const match = api.userAgent.match(/^GitHub(GhostPilot|WorkspaceEditor)\/[\\.\d]+$/)
      expect(match).not.toBeNull()
    })
  })
})
