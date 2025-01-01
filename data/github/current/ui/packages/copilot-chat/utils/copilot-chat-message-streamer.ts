import type {MessageStreamingResponse, MessageStreamingResponseError} from './copilot-chat-types'

const MESSAGE_DELIMITER = '\n\n'
const MESSAGE_REGEXP = /^data:\s+/
const MESSAGE_END = '[DONE]'

export class CopilotStreamingError extends Error {
  error: MessageStreamingResponseError

  constructor(error: MessageStreamingResponseError) {
    super(error.description)
    this.error = error
    this.name = 'CopilotStreamingError'
  }
}

type Reader = ReadableStreamDefaultReader<Uint8Array>

export class CopilotChatMessageStreamer<T extends {type?: string} = MessageStreamingResponse> {
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
        const error: MessageStreamingResponseError = {
          type: 'error',
          errorType: 'networkError',
          description: 'NETWORK_CONNECTION_INTERRUPTED',
        }

        throw new CopilotStreamingError(error)
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
        if (parsedMessage?.type === 'complete') return

        // Move to the next potential message in this chunk.
        partialMessage = partialMessage.slice(messageEnd + MESSAGE_DELIMITER.length)
      }
    }
  }

  async stop() {
    return this.reader.cancel()
  }
}
