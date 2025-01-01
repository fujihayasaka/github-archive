// Default maximum width for the content area, used as the maximum width for images spanning entire width of content area.
export const MAX_CONTENT_WIDTH = 1248

const MOBILE_BREAKPOINT = 480
const TABLET_BREAKPOINT = 768
const DESKTOP_BREAKPOINT = 1280

const MEDIA_BREAKPOINTS = [MOBILE_BREAKPOINT, TABLET_BREAKPOINT, DESKTOP_BREAKPOINT]

type ImageSource = {
  srcset: string
  media: string
}

type ResponsiveImageMap = {
  narrow?: string
  regular?: string
  wide?: string
}

type GetImageSourcesOptions = {
  maxWidth?: number
  disableDprScaling?: boolean
  quality?: number
}

/**
 * Constructs a URL with query parameters.
 *
 * @param baseUrl - The base URL of the image.
 * @param params - An object where keys are query parameters and values are their corresponding values.
 * @returns A properly formatted URL with query parameters.
 */
export const buildImageUrl = (baseUrl: string, params: Record<string, string | number | undefined>): string => {
  const queryString = Object.entries(params)
    .filter(([_, value]) => value !== undefined)
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value as string | number)}`)
    .join('&')

  return queryString ? `${baseUrl}?${queryString}` : baseUrl
}

/**
 * Generates responsive image sources for optimal performance.
 *
 * @param url - The base URL of the image.
 * @param options - Optional configuration object
 * @returns An array of objects containing `srcset` and `media` properties.
 */
export const getImageSources = (url: string, options: GetImageSourcesOptions = {}): ImageSource[] => {
  const {maxWidth, disableDprScaling = false, quality = 90} = options

  const createSrcset = (width?: number) => {
    if (width) {
      return disableDprScaling
        ? buildImageUrl(url, {w: width * 2, fm: 'webp', q: quality})
        : `${buildImageUrl(url, {w: width, fm: 'webp', q: quality})} 1x, ${buildImageUrl(url, {
            w: width * 2,
            fm: 'webp',
            q: quality,
          })} 2x`
    }
    return buildImageUrl(url, {fm: 'webp', q: quality})
  }

  const sources = MEDIA_BREAKPOINTS.map(size => {
    // Ensure the size does not exceed the maxWidth (if provided)
    const sizeValue = maxWidth && size > maxWidth ? maxWidth : size
    return {
      srcset: createSrcset(sizeValue),
      media: `(max-width: ${size}px)`,
    }
  })

  const desktopSource = {
    srcset: createSrcset(maxWidth),
    media: `(min-width: ${DESKTOP_BREAKPOINT}px)`,
  }

  return [...sources, desktopSource]
}

/**
 * Generates structured image sources that work with Primer brand props.
 *
 * @param url - The base URL of the image.
 * @param options - Optional configuration object
 * @returns An object containing { narrow, regular, wide } image sources.
 */
export const getStructuredImageSources = (url: string, options: GetImageSourcesOptions = {}): ResponsiveImageMap => {
  const sources = getImageSources(url, {disableDprScaling: true, ...options})

  return {
    narrow: sources[1]?.srcset,
    regular: sources[2]?.srcset,
    wide: sources[3]?.srcset,
  }
}
