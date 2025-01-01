import {getImageSources, buildImageUrl, getStructuredImageSources} from '../../../lib/utils/images'

describe('buildImageUrl', () => {
  const baseUrl = 'https://example.com/image.jpg'

  it('constructs a URL with single query parameter', () => {
    const result = buildImageUrl(baseUrl, {w: 800})
    expect(result).toBe('https://example.com/image.jpg?w=800')
  })

  it('constructs a URL with multiple query parameters', () => {
    const result = buildImageUrl(baseUrl, {w: 800, fm: 'webp', q: 90})
    expect(result).toBe('https://example.com/image.jpg?w=800&fm=webp&q=90')
  })

  it('removes undefined query parameters', () => {
    const result = buildImageUrl(baseUrl, {w: 800, fm: undefined, q: 90})
    expect(result).toBe('https://example.com/image.jpg?w=800&q=90')
  })

  it('returns base URL if no valid parameters are provided', () => {
    const result = buildImageUrl(baseUrl, {})
    expect(result).toBe(baseUrl)
  })

  it('correctly encodes special characters in query parameters', () => {
    const result = buildImageUrl(baseUrl, {key: 'value with spaces', special: '@&'})
    expect(result).toBe('https://example.com/image.jpg?key=value%20with%20spaces&special=%40%26')
  })
})

describe('getImageSources', () => {
  const baseUrl = 'https://example.com/image.jpg'

  it('generates sources for default breakpoints without maxImageWidth', () => {
    const result = getImageSources(baseUrl)

    expect(result).toEqual([
      {
        srcset: `${baseUrl}?w=480&fm=webp&q=90 1x, ${baseUrl}?w=960&fm=webp&q=90 2x`,
        media: '(max-width: 480px)',
      },
      {
        srcset: `${baseUrl}?w=768&fm=webp&q=90 1x, ${baseUrl}?w=1536&fm=webp&q=90 2x`,
        media: '(max-width: 768px)',
      },
      {
        srcset: `${baseUrl}?w=1280&fm=webp&q=90 1x, ${baseUrl}?w=2560&fm=webp&q=90 2x`,
        media: '(max-width: 1280px)',
      },
      {
        srcset: `${baseUrl}?fm=webp&q=90`,
        media: '(min-width: 1280px)',
      },
    ])
  })

  it('respects maxImageWidth for all breakpoints', () => {
    const result = getImageSources(baseUrl, {maxWidth: 800})

    expect(result).toEqual([
      {
        srcset: `${baseUrl}?w=480&fm=webp&q=90 1x, ${baseUrl}?w=960&fm=webp&q=90 2x`,
        media: '(max-width: 480px)',
      },
      {
        srcset: `${baseUrl}?w=768&fm=webp&q=90 1x, ${baseUrl}?w=1536&fm=webp&q=90 2x`,
        media: '(max-width: 768px)',
      },
      {
        srcset: `${baseUrl}?w=800&fm=webp&q=90 1x, ${baseUrl}?w=1600&fm=webp&q=90 2x`,
        media: '(max-width: 1280px)',
      },
      {
        srcset: `${baseUrl}?w=800&fm=webp&q=90 1x, ${baseUrl}?w=1600&fm=webp&q=90 2x`,
        media: '(min-width: 1280px)',
      },
    ])
  })

  it('generates duplicate sources if maxImageWidth is smaller than the smallest breakpoint', () => {
    const result = getImageSources(baseUrl, {maxWidth: 400})

    expect(result).toEqual([
      {
        srcset: `${baseUrl}?w=400&fm=webp&q=90 1x, ${baseUrl}?w=800&fm=webp&q=90 2x`,
        media: '(max-width: 480px)',
      },
      {
        srcset: `${baseUrl}?w=400&fm=webp&q=90 1x, ${baseUrl}?w=800&fm=webp&q=90 2x`,
        media: '(max-width: 768px)',
      },
      {
        srcset: `${baseUrl}?w=400&fm=webp&q=90 1x, ${baseUrl}?w=800&fm=webp&q=90 2x`,
        media: '(max-width: 1280px)',
      },
      {
        srcset: `${baseUrl}?w=400&fm=webp&q=90 1x, ${baseUrl}?w=800&fm=webp&q=90 2x`,
        media: '(min-width: 1280px)',
      },
    ])
  })
})

describe('getStructuredImageSources', () => {
  const baseUrl = 'https://example.com/image.jpg'

  it('returns structured image sources for high-resolution backgrounds', () => {
    const result = getStructuredImageSources(baseUrl, {maxWidth: 800})

    expect(result).toEqual({
      narrow: `${baseUrl}?w=1536&fm=webp&q=90`,
      regular: `${baseUrl}?w=1600&fm=webp&q=90`,
      wide: `${baseUrl}?w=1600&fm=webp&q=90`,
    })
  })

  it('respects custom quality setting', () => {
    const result = getStructuredImageSources(baseUrl, {maxWidth: 1000, quality: 80})

    expect(result).toEqual({
      narrow: `${baseUrl}?w=1536&fm=webp&q=80`,
      regular: `${baseUrl}?w=2000&fm=webp&q=80`,
      wide: `${baseUrl}?w=2000&fm=webp&q=80`,
    })
  })
})
