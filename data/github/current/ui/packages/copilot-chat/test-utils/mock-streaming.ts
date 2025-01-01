//eslint-disable-next-line import/no-nodejs-modules -- we want to mock a fetch response with a ReadableStream
import {ReadableStream} from 'node:stream/web'

import {within} from '@testing-library/react'

import type {MessageStreamingResponse} from '../utils/copilot-chat-types'
import {EventStreamResponse} from './mock-interactive'

/**
 * MessageStreamingGates are used to pause streaming to allow testing. When a gate is reached, the stream will resolve
 * the entry promise, and await the exit promise. The test code should await the entry promise, test at
 * that point, and then resolve the exit promise to allow testing to continue.
 */
export interface MessageStreamingGate {
  type: 'testing-gate'
  name: string
  entry: {
    promise: Promise<void>
    resolve: () => void
  }
  exit: {
    promise: Promise<void>
    resolve: () => void
  }
}

export type TestMessageStream = ReadonlyArray<MessageStreamingResponse | MessageStreamingGate>

/**
 * Generates an EventStreamResponse suitable to pass to mockResponses from a TestMessageStream.
 */
export function mockEventStreamReplay(replay: TestMessageStream): EventStreamResponse {
  const encoder = new TextEncoder()
  const buffer = replay.toReversed()
  const stream = new ReadableStream<Uint8Array>({
    async pull(controller) {
      while (buffer.length > 0) {
        const message = buffer.pop()!

        if (message.type === 'testing-gate') {
          // resolve the entry promise to let the test driver know we're at the gate
          message.entry.resolve()
          // wait for the test code to resolve the exit promise
          await message.exit.promise
        } else {
          controller.enqueue(encoder.encode(`data: ${JSON.stringify(message)}\n\n`))
        }
      }

      controller.close()
    },
  })
  return new EventStreamResponse(stream)
}

export function makeGate(name: string): MessageStreamingGate {
  let gateEntryResolver: () => void
  const gateEntryPromise = new Promise<void>(resolve => (gateEntryResolver = resolve))
  let gateExitResolver: () => void
  const gateExitPromise = new Promise<void>(resolve => (gateExitResolver = resolve))
  return {
    type: 'testing-gate',
    name,
    entry: {
      promise: gateEntryPromise,
      resolve: gateEntryResolver!,
    },
    exit: {
      promise: gateExitPromise,
      resolve: gateExitResolver!,
    },
  }
}

/**
 * Extracts all gates from a stream.
 */
export function extractGates(stream: TestMessageStream): MessageStreamingGate[] {
  return stream.filter((message): message is MessageStreamingGate => message.type === 'testing-gate')
}

/** Find streaming message content (split up by words because each word gets wrapped in a span tag). */
export async function findStreamingContent(container: HTMLElement, content: string) {
  await Promise.all(
    content.split(' ').map(async word => expect(await within(container).findByText(word)).toBeVisible()),
  )
}
