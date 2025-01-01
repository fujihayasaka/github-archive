import '../promise-with-resolvers-polyfill'

describe('promiseWithResolvers', () => {
  it('creates a PromiseLike instance with additional resolve and reject properties', () => {
    const promiseWithResolvers = Promise.withResolvers()
    expect(promiseWithResolvers).toHaveProperty('promise', expect.any(Promise))
    expect(promiseWithResolvers).toHaveProperty('resolve', expect.any(Function))
    expect(promiseWithResolvers).toHaveProperty('reject', expect.any(Function))
  })

  it('resolves the promise externally', async () => {
    const promiseWithResolvers = Promise.withResolvers<number>()
    promiseWithResolvers.resolve(4)
    await expect(promiseWithResolvers.promise).resolves.toBe(4)
  })

  it('resolves the promise externally destructured', async () => {
    const promiseWithResolvers = Promise.withResolvers<number>()
    const {resolve} = promiseWithResolvers
    resolve(4)
    await expect(promiseWithResolvers.promise).resolves.toBe(4)
  })

  it('rejects the promise externally', async () => {
    const promiseWithResolvers = Promise.withResolvers<number>()
    const err = new Error('expected error rejection')
    promiseWithResolvers.reject(err)
    await expect(promiseWithResolvers.promise).rejects.toBe(err)
  })

  it('rejects the promise externally destructured', async () => {
    const promiseWithResolvers = Promise.withResolvers<number>()
    const {reject} = promiseWithResolvers
    const err = new Error('expected error rejection')
    reject(err)
    await expect(promiseWithResolvers.promise).rejects.toBe(err)
  })

  it('can chain promises', async () => {
    const VALUE = 4
    const CHAIN_ADD = 2
    const promiseWithResolvers = Promise.withResolvers<number>()
    // eslint-disable-next-line github/no-then
    const chained = promiseWithResolvers.promise.then(y => y + CHAIN_ADD)
    promiseWithResolvers.resolve(VALUE)
    await expect(chained).resolves.toBe(VALUE + CHAIN_ADD)
  })

  it('can chain failures', async () => {
    const promiseWithResolvers = Promise.withResolvers<number>()
    const err = new Error('invalid')
    const secondErr = new Error('second err')
    // eslint-disable-next-line github/no-then
    const chained = promiseWithResolvers.promise.catch(() => {
      throw secondErr
    })
    promiseWithResolvers.reject(err)
    await expect(promiseWithResolvers.promise).rejects.toBe(err)
    await expect(chained).rejects.toBe(secondErr)
  })

  it('calls finally callback', async () => {
    const finallyCall = jest.fn()
    const VALUE = 4
    const promiseWithResolvers = Promise.withResolvers<number>()
    promiseWithResolvers.promise.finally(finallyCall)
    promiseWithResolvers.resolve(VALUE)

    await expect(promiseWithResolvers.promise).resolves.toBe(VALUE)
    expect(finallyCall).toHaveBeenNthCalledWith(1)
  })
})
