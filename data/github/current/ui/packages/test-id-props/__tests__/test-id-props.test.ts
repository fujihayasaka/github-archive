import {testIdProps} from '../test-id-props'

const mockAppEnv = jest.fn().mockName('appEnv')

jest.mock('../utils', () => ({
  appEnv: () => mockAppEnv(),
}))

describe('testIdProps', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  test('returns empty object in production', () => {
    mockAppEnv.mockReturnValue('production')
    expect(testIdProps('foo')).toEqual({})
  })

  test('returns data-testid attribute in test environment', () => {
    mockAppEnv.mockReturnValue('test')
    expect(testIdProps('foo')).toEqual({'data-testid': 'foo'})
  })

  test('returns data-testid attribute in development environment', () => {
    mockAppEnv.mockReturnValue('development')
    expect(testIdProps('foo')).toEqual({'data-testid': 'foo'})
  })
})
