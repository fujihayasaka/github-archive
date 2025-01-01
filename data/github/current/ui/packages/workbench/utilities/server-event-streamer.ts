import type {ServerEvent} from '../types/server-event-types'

const MESSAGE_DELIMITER = '\n\n'
const MESSAGE_REGEXP = /^data:\s+/
const MESSAGE_END = '[DONE]'

type Reader = ReadableStreamDefaultReader<Uint8Array>

export class ServerEventStreamer<T extends {type?: string} = ServerEvent> {
  reader: Reader

  constructor(reader: Reader) {
    this.reader = reader
  }

  async *stream(): AsyncIterable<T> {
    const utf8Decoder = new TextDecoder('utf-8')

    let partialMessage = ''

    for (;;) {
      let value: Uint8Array | undefined
      let done: boolean
      try {
        ;({value, done} = await this.reader.read())
      } catch {
        throw new Error('Error reading from stream')
      }

      if (done) break

      // Keep track of partial messages in between stream chunks.
      partialMessage += utf8Decoder.decode(value)

      for (;;) {
        // Find the end of the first message. If there isn't one we need to get the next chunk in the stream.
        const messageEnd = partialMessage.indexOf(MESSAGE_DELIMITER)
        if (messageEnd === -1) break

        const rawMessage = partialMessage.slice(0, messageEnd).replace(MESSAGE_REGEXP, '')

        // Check for copilot agent stream end.
        if (rawMessage === MESSAGE_END) return

        let parsedMessage: T
        try {
          parsedMessage = JSON.parse(rawMessage)
        } catch {
          // Skip this message and continue with the next one
          partialMessage = partialMessage.slice(messageEnd + MESSAGE_DELIMITER.length)
          continue
        }

        yield parsedMessage

        // If we get a complete or error message, then we know we are done and can exit early.
        if (parsedMessage?.type === 'complete') return

        // Move to the next potential message in this chunk.
        partialMessage = partialMessage.slice(messageEnd + MESSAGE_DELIMITER.length)
      }
    }
  }

  async stop() {
    try {
      return await this.reader.cancel()
    } catch {
      return Promise.resolve()
    }
  }
}
