import {getCPUBucket} from '../cpu-bucket'

describe('getCPUBucket', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('returns unknown if value is invalid', () => {
    jest.spyOn(navigator, 'hardwareConcurrency', 'get').mockReturnValue(0)
    expect(getCPUBucket()).toBe('unknown')
  })

  test('sm for 1 and 2 cpus', () => {
    jest.spyOn(navigator, 'hardwareConcurrency', 'get').mockReturnValue(1)
    expect(getCPUBucket()).toBe('sm')
    jest.spyOn(navigator, 'hardwareConcurrency', 'get').mockReturnValue(2)
    expect(getCPUBucket()).toBe('sm')
  })

  test('md for 3 and 4 cpus', () => {
    jest.spyOn(navigator, 'hardwareConcurrency', 'get').mockReturnValue(3)
    expect(getCPUBucket()).toBe('md')
    jest.spyOn(navigator, 'hardwareConcurrency', 'get').mockReturnValue(4)
    expect(getCPUBucket()).toBe('md')
  })

  test('lg for 5 to 8 cpus', () => {
    jest.spyOn(navigator, 'hardwareConcurrency', 'get').mockReturnValue(5)
    expect(getCPUBucket()).toBe('lg')
    jest.spyOn(navigator, 'hardwareConcurrency', 'get').mockReturnValue(8)
    expect(getCPUBucket()).toBe('lg')
  })

  test('xlg for anything over 8 cpus', () => {
    jest.spyOn(navigator, 'hardwareConcurrency', 'get').mockReturnValue(9)
    expect(getCPUBucket()).toBe('xlg')
    jest.spyOn(navigator, 'hardwareConcurrency', 'get').mockReturnValue(32)
    expect(getCPUBucket()).toBe('xlg')
  })
})
