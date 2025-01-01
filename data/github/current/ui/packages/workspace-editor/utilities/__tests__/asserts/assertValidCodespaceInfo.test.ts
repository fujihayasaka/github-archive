// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {AssertionError} from '../../../errors'
import {assertDefined, assertValidCodespaceInfo} from '../../asserts'

describe('assertValidCodespaceInfo', () => {
  it('should throw if `environment_data` is undefined', () => {
    const data = {
      cloud_environment: {},
      foo: true,
    }
    expect(() => {
      assertValidCodespaceInfo(data, 'Must have `environment_data` defined')
    }).toThrow('Must have `environment_data` defined: Codespace info is not valid because environment data is not set.')
  })

  it('should throw if `cloud_environment` is undefined', () => {
    const data = {
      environment_data: {},
      bar: 21,
    }
    expect(() => {
      assertValidCodespaceInfo(data, 'Must have `cloud_environment` defined')
    }).toThrow(
      'Must have `cloud_environment` defined: Codespace info is not valid because cloud environment data is not set.',
    )
  })

  it('should not throw if `environment_data` and `cloud_environment` are defined', () => {
    const data = {
      environment_data: {},
      cloud_environment: {},
    }
    expect(() => {
      assertValidCodespaceInfo(data, 'Error prefix')
    }).not.toThrow('Error prefix: Codespace info is not valid because cloud environment data is not set.')
  })

  it('should ignore additional fields', () => {
    const data = {
      environment_data: {},
      cloud_environment: {},
      bar: true,
      foo: '21',
      baz: 12,
    }
    expect(() => {
      assertValidCodespaceInfo(data, 'Error prefix')
    }).not.toThrow('Error prefix: Codespace info is not valid because cloud environment data is not set.')
  })

  it('should throw assertion error by default', async () => {
    let thrownError: AssertionError | undefined
    try {
      assertValidCodespaceInfo({}, 'WAT')
    } catch (e) {
      thrownError = e as AssertionError
    }

    expect(thrownError).toBeInstanceOf(AssertionError)
    assertDefined(thrownError, 'Must throw an error.')

    expect(thrownError.message).toEqual('WAT: Codespace info is not valid because environment data is not set.')
  })
})
