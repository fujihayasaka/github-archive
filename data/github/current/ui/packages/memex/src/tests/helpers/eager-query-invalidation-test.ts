import {EagerQueryInvalidation} from '../../client/state-providers/data-refresh/eager-query-invalidation'

describe('EagerQueryInvalidation', () => {
  it('stores request IDs in a circular buffer', () => {
    const eqi = new EagerQueryInvalidation(3)
    eqi.register('1')
    eqi.register('2')
    eqi.register('3')

    // Before we exceed the size of the buffer, all previously registered IDs should be present.
    expect(eqi.has('1')).toBe(true)
    eqi.register('4')

    // Now that we have exceeded the size of the buffer, the oldest ID should have been overwritten.
    expect(eqi.has('1')).toBe(false)

    expect(eqi.has('2')).toBe(true)
    expect(eqi.has('3')).toBe(true)
    expect(eqi.has('4')).toBe(true)
  })
})
