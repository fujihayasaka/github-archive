import type {CAPIResponse} from './types'

const MESSAGE_DELIMITER = '\n\n'
const MESSAGE_REGEXP = /^data:\s+/
const MESSAGE_END = '[DONE]'

type Reader = ReadableStreamDefaultReader<Uint8Array>

export class Streamer<T extends CAPIResponse> {
  reader: Reader

  constructor(reader: Reader) {
    this.reader = reader
  }

  async *stream(): AsyncIterable<T> {
    const utf8Decoder = new TextDecoder('utf-8')

    let partialMessage = ''

    for (;;) {
      let value
      let done
      try {
        ;({value, done} = await this.reader.read())
      } catch {
        // const error: MessageStreamingResponseError = {
        //   type: 'error',
        //   errorType: 'networkError',
        //   description: 'NETWORK_CONNECTION_INTERRUPTED',
        // }
        // throw new CopilotStreamingError(error)
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

        const parsedMessage: T = JSON.parse(rawMessage)

        yield parsedMessage

        // If we get a complete or error message, then we know we are done and can exit early.
        if (parsedMessage?.choices[0]?.finish_reason === 'stop') return

        // Move to the next potential message in this chunk.
        partialMessage = partialMessage.slice(messageEnd + MESSAGE_DELIMITER.length)
      }
    }
  }

  async stop() {
    return this.reader.cancel()
  }
}
