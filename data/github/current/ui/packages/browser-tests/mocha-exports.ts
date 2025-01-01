import type Mocha from 'mocha'

type TestHelpers = {
  describe: Mocha.SuiteFunction
  it: Mocha.TestFunction
  beforeEach: Mocha.HookFunction
  beforeAll: Mocha.HookFunction
  afterEach: Mocha.HookFunction
  afterAll: Mocha.HookFunction
}

// eslint-disable-next-line import/no-mutable-exports
let testHelpers: TestHelpers = {
  describe: Object.assign(
    (): Mocha.Suite => {
      throw new Error('describe is not defined')
    },
    {
      only: (): Mocha.Suite => {
        throw new Error('describe.only is not defined')
      },
      skip: (): Mocha.Suite => {
        throw new Error('describe.skip is not defined')
      },
    },
  ),
  it: Object.assign(
    (): Mocha.Test => {
      throw new Error('it is not defined')
    },
    {
      only: (): Mocha.Test => {
        throw new Error('it.only is not defined')
      },
      skip: (): Mocha.Test => {
        throw new Error('it.skip is not defined')
      },
      retries: (): Mocha.Test => {
        throw new Error('it.retries is not defined')
      },
    },
  ),
  beforeEach: () => {
    throw new Error('beforeEach is not defined')
  },
  beforeAll: () => {
    throw new Error('before is not defined')
  },
  afterEach: () => {
    throw new Error('afterEach is not defined')
  },
  afterAll: () => {
    throw new Error('after is not defined')
  },
}

try {
  const _describe = describe
  const _it = it
  const _beforeEach = beforeEach
  const _before = before
  const _afterEach = afterEach
  const _after = after

  testHelpers = {
    describe: _describe,
    it: _it,
    beforeEach: _beforeEach,
    beforeAll: _before,
    afterEach: _afterEach,
    afterAll: _after,
  }
} catch {
  // Vitest does not have describe, it, beforeEach, etc. functions in the global scope.
}

export default testHelpers
