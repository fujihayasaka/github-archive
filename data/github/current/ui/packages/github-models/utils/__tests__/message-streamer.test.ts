import {MessageStreamer} from '../message-streamer'
import {MockReader} from './mocks'

describe('MessageStreamer', () => {
  test('handles an empty stream', async () => {
    const streamer = new MessageStreamer(new MockReader([]))
    const result = []

    for await (const chunk of streamer.stream()) {
      result.push(chunk)
    }

    expect(result).toHaveLength(0)
  })

  test('streams a single chunk', async () => {
    const streamer = new MessageStreamer(
      new MockReader([{choices: [{index: 0, finish_reason: 'stop', delta: {content: 'hello'}}]}]),
    )
    const result = []

    for await (const streamedChunk of streamer.stream()) {
      result.push(streamedChunk)
    }

    expect(result).toHaveLength(1)
    expect(result[0]?.choices).toHaveLength(1)
    expect(result[0]?.choices[0]?.index).toBe(0)
    expect(result[0]?.choices[0]?.finish_reason).toBe('stop')
    expect(result[0]?.choices[0]?.delta?.content).toBe('hello')
  })

  test('allows a stream to be stopped', async () => {
    const streamer = new MessageStreamer(
      new MockReader([
        {choices: [{index: 0, finish_reason: null, delta: {content: 'hello'}}]},
        {choices: [{index: 0, finish_reason: null, delta: {content: ' my '}}]},
        {choices: [{index: 0, finish_reason: 'stop', delta: {content: 'friend.'}}]},
      ]),
    )
    const result = []
    let remaining = 2

    for await (const chunk of streamer.stream()) {
      result.push(chunk)
      remaining--
      if (remaining === 0) await streamer.stop()
    }

    expect(result).toHaveLength(2)
    const last = result.pop()!
    expect(last.choices).toHaveLength(1)
    expect(last.choices[0]?.index).toBe(0)
    expect(last.choices[0]?.finish_reason).toBeNull()
    expect(last.choices[0]?.delta?.content).toBe(' my ')
  })
})
