import type {ChatCompletionChunk, Reader} from '../../types'

export class MockReader implements Reader {
  chunks: ChatCompletionChunk[]
  encoder: TextEncoder

  constructor(chunks: ChatCompletionChunk[]) {
    this.chunks = chunks
    this.encoder = new TextEncoder()
  }

  read(): Promise<ReadableStreamReadResult<Uint8Array>> {
    if (this.chunks.length > 0) {
      const chunk = this.chunks.shift()
      const data = `data: ${JSON.stringify(chunk)}\n\n`

      return Promise.resolve({value: this.encoder.encode(data), done: false})
    }

    return Promise.resolve({done: true})
  }

  releaseLock() {}
  close() {}

  cancel() {
    this.chunks = []
    return Promise.resolve(undefined)
  }

  get closed() {
    return Promise.resolve(undefined)
  }
}
