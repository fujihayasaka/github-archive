import {setupCPUCookie} from '../cpu-cookie'
import {setCookie} from '@github-ui/cookies'

jest.mock('@github-ui/cookies', () => ({
  setCookie: jest.fn(),
}))

describe('setupCPUCookie', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('returns unknown if CPU cores number is invalid', () => {
    jest.spyOn(navigator, 'hardwareConcurrency', 'get').mockReturnValue(0)
    setupCPUCookie()

    expect(setCookie).toHaveBeenCalledWith('cpu_bucket', 'unknown')
  })

  test('returns a bucket if CPU cores number is valid', () => {
    jest.spyOn(navigator, 'hardwareConcurrency', 'get').mockReturnValue(2)
    setupCPUCookie()

    expect(setCookie).toHaveBeenCalledWith('cpu_bucket', 'sm')
  })
})
