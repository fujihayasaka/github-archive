import {logError} from './console'

export async function parseResponseStream(
  stream: ReadableStream<Uint8Array>,
  _onPartialResult?: (result: string) => void,
): Promise<string | undefined> {
  const decoder = new TextDecoder()
  const reader = stream.getReader()
  let chunks = ''

  while (true) {
    const {done, value} = await reader.read()
    if (done) {
      return
    }

    const chunk = decoder.decode(value)
    chunks += chunk

    // Last chunk we care about, so we can now assemble the completion.
    if (chunk.endsWith('\n\ndata: [DONE]\n\n')) {
      const cumulativeResult = processChunks(chunks)
      return cumulativeResult
    } else {
      // todo: can streaming work here?
      // onPartialResult?.(cumulativeResult)
    }
  }
}

function processChunks(chunks: string): string {
  chunks = chunks.replace('data: ', '').replace('\n\ndata: [DONE]\n\n', '')

  const choices = chunks.split('\n\ndata: ').map(completion => {
    try {
      const choice = JSON.parse(completion).choices[0]
      return choice?.delta?.content ?? ''
    } catch (e) {
      // Sometimes we don't get JSON -- don't die for it, just skip
      logError(`completion: '${completion}'\nerror: ${e}`)
    }
  })

  return choices.join('')
}
