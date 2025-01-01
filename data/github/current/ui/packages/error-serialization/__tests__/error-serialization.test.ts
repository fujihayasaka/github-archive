import {formatError, stacktrace} from '../error-serialization'

describe('error-serialization', () => {
  test('formatError', () => {
    const error = new Error('test')
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ;(error as any).catalogService = 'some-service'
    expect(formatError(error)).toEqual({
      type: 'Error',
      value: 'test',
      stacktrace: stacktrace(error),
      catalogService: 'some-service',
    })
  })

  test('stacktrace', () => {
    const error = new Error('test')
    const stack = stacktrace(error)

    expect(stack.length).toBeGreaterThan(1)

    const firstLine = stack[0]!
    expect(firstLine.filename).toContain('error-serialization.test.ts')
    expect(firstLine.function).toBe('Object.<anonymous>')
    // assert colno is a number
    expect(parseInt(firstLine.colno!)).toBeGreaterThan(1)
    expect(parseInt(firstLine.lineno)).toBeGreaterThan(1)
  })
})
