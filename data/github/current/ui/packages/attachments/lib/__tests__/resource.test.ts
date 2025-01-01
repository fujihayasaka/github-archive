import {resource} from '../resource'

describe('resource', () => {
  it('creates', () => {
    expect(() => {
      resource(jest.fn().mockResolvedValue(Promise.resolve('hello')))
    }).not.toThrow()
  })

  it('allows loading some value from the loader', async () => {
    const res = resource(jest.fn().mockResolvedValue(Promise.resolve('hello')))
    const result = await res.load()
    expect(result).toBe('hello')
  })

  it('should only call the loader once', async () => {
    const loader = jest.fn().mockResolvedValue(Promise.resolve('hello'))
    const res = resource(loader)
    await res.load()
    await res.load()
    expect(loader).toHaveBeenCalledTimes(1)
  })

  it('throws a promise when reading before its resolved', () => {
    const res = resource(jest.fn().mockResolvedValue(Promise.resolve('hello')))
    expect(() => {
      res.read()
    }).toThrow(Promise)
  })

  it('synchronously returns the value after resource is loaded', async () => {
    const res = resource(jest.fn().mockResolvedValue(Promise.resolve('hello')))
    await res.load()
    // Notice no await here, read should be sync
    expect(res.read()).toBe('hello')
  })

  it('a rejected promise throw that error', async () => {
    const error = new Error()
    const loader = jest.fn().mockResolvedValue(Promise.reject(error))

    const res = resource(loader)

    let didCatch = false

    try {
      await res.load()
    } catch (e: unknown) {
      expect(e).toBe(error)
      didCatch = true
    }

    expect(didCatch).toBe(true)
    expect(loader).toHaveBeenCalledTimes(1)

    // Calling load again, should still throw the error, but the loader shouldnt be called again
    didCatch = false

    try {
      await res.load()
    } catch (e: unknown) {
      expect(e).toBe(error)
      didCatch = true
    }

    expect(didCatch).toBe(true)
    expect(loader).toHaveBeenCalledTimes(1)
  })
})
