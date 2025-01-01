import React from 'react'

import type {StepMessage} from '../../types'
import {useAuthToken} from './auth'

export function useSession(prompt: string, maxEpisodeSteps: number) {
  const tokens = useAuthToken()

  const [steps, setSteps] = React.useState<StepMessage[]>([])
  const [loading, setLoading] = React.useState(true)

  const initialized = React.useRef(false)

  const abort = React.useRef<AbortController | null>(null)
  React.useEffect(() => {
    abort.current = new AbortController()
    return () => abort.current?.abort()
  }, [])

  React.useEffect(() => {
    if (!initialized.current) {
      initialized.current = true

      setSteps([])
      setLoading(true)
      ;(async function () {
        const res = await callEndpoint('/cua/proxy', await tokens, {
          method: 'POST',
          body: JSON.stringify({prompt, max_episode_steps: maxEpisodeSteps}),
          signal: abort.current?.signal,
        })

        try {
          for await (const step of streamParser(res)) {
            if (abort.current?.signal.aborted) return

            if (!step.meta) {
              continue
            }
            let message: StepMessage = JSON.parse(step.meta)
            // Note: Message is double encoded json, so we parse twice.
            if (typeof message === 'string') message = JSON.parse(message)
            setSteps(current => [...current, message])
          }
        } finally {
          setLoading(false)
        }
      })()
    }
  }, [prompt, maxEpisodeSteps, tokens])

  return {
    loading,
    steps,
  }
}

async function callEndpoint(endpoint: string, tokens: {cua: string; github: string}, options: RequestInit) {
  const url = new URL(endpoint, 'https://models.github.ai/')
  const request = new Request(url, options)

  request.headers.set('Content-Type', 'application/json')
  request.headers.set('Authorization', tokens.github)
  request.headers.set('X-GitHub-CUA-Token', tokens.cua)
  request.headers.set('request-id', globalThis.crypto.randomUUID())

  const res = await fetch(request)
  if (!res.ok) throw new Error(await res.text())
  return res
}

async function* streamParser(res: Response) {
  const reader = res.body?.getReader()
  if (!reader) throw new Error('Unexpected missing reader')

  const decoder = new TextDecoder('utf-8')

  let buffer = ''
  let result: ReadableStreamReadResult<Uint8Array>
  while (!(result = await reader.read()).done) {
    const chunk = decoder.decode(result.value, {stream: true})
    buffer += chunk

    // Our boundary is delineated by newlines, and assume there are no json that split across lines.
    // eg:
    // {"foo": "bar"}\n
    // {"baz": "qux"}\n
    //
    // Each chunk may be split at random spots, like:
    // {"foo": "ba
    // r"}\n{"baz": "qux"}\n
    //
    // So look for a newline, and everything before it is a valid chunk.
    let boundaryIndex = buffer.indexOf('\n')

    // Look for as many "strings of json" as we can in this chunk,
    //   it might be more than one, than wait for the next iteration.
    while (boundaryIndex !== -1) {
      const current = buffer.slice(0, boundaryIndex)

      // NOTE: failing to parse, will just throw errors, which is fine for now.
      yield JSON.parse(current)

      buffer = buffer.slice(boundaryIndex + 1) // 1 = newline length.
      boundaryIndex = buffer.indexOf('\n')
    }
  }
}
