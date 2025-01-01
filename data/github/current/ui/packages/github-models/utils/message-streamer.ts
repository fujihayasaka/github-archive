import type {ChatCompletionChunk, Reader} from '../types'
import {TimeoutError} from './playground-types'

const MESSAGE_DELIMITER = '\n\n'
const MESSAGE_REGEXP = /^data:\s+/

export class MessageStreamer {
  reader: Reader
  private chunkTimeoutId: ReturnType<typeof setTimeout> | undefined
  private chunkTimeoutMs: number | undefined
  private abortController: AbortController | undefined

  constructor(
    reader: Reader,
    chunkTimeoutMs: number | undefined = undefined,
    abortController: AbortController | undefined = undefined,
  ) {
    this.reader = reader
    this.abortController = abortController
    this.chunkTimeoutMs = chunkTimeoutMs || 5000
  }

  async *stream(): AsyncIterable<ChatCompletionChunk> {
    const utf8Decoder = new TextDecoder('utf-8')

    let partialMessage = ''

    for (;;) {
      let value
      let done
      try {
        this.resetChunkTimeout()
        ;({value, done} = await this.reader.read())
      } catch (err) {
        if (this.abortController?.signal?.aborted) {
          throw this.abortController.signal.reason
        }
        throw err
      } finally {
        this.clearChunkTimeout()
      }

      if (done) break

      // Keep track of partial messages in between stream chunks.
      partialMessage += utf8Decoder.decode(value)

      for (;;) {
        // If we get a DONE chunk, we can exit early.
        if (partialMessage.startsWith('data: [DONE]')) return

        // Find the end of the first message. If there isn't one we need to get the next chunk in the stream.
        const messageEnd = partialMessage.indexOf(MESSAGE_DELIMITER)
        if (messageEnd === -1) break

        const rawMessage = partialMessage.slice(0, messageEnd).replace(MESSAGE_REGEXP, '')
        // Empty chunk, nothing to do.
        if (rawMessage === '') {
          // Move to the next potential message in this chunk.
          partialMessage = partialMessage.slice(messageEnd + MESSAGE_DELIMITER.length)
          continue
        }
        const parsedMessage: ChatCompletionChunk = JSON.parse(rawMessage)

        yield parsedMessage

        // Move to the next potential message in this chunk.
        partialMessage = partialMessage.slice(messageEnd + MESSAGE_DELIMITER.length)
      }
    }
  }

  async stop() {
    return this.reader.cancel()
  }

  clearChunkTimeout() {
    if (this.chunkTimeoutId) {
      clearTimeout(this.chunkTimeoutId)
      this.chunkTimeoutId = undefined
    }
  }

  resetChunkTimeout() {
    if (!this.abortController || !this.chunkTimeoutMs) {
      return
    }

    this.clearChunkTimeout()
    this.chunkTimeoutId = setTimeout(() => {
      this.abortController?.abort(new TimeoutError('Sorry, this is taking longer than usual.'))
    }, this.chunkTimeoutMs)
  }
}
