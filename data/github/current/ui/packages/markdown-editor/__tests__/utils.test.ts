import type {ImageDimensions} from '../types'
import {markdownImageTag} from '../utils'

const RETINA_PPI = 144

it('should return an img tag with half width for retina images', () => {
  const dimensions: ImageDimensions = {width: 200, height: 100, ppi: RETINA_PPI}
  const src = 'http://example.com/image.png'
  const alt = 'Example Image'

  const result = markdownImageTag(dimensions, src, alt)
  expect(result).toBe('<img width="100" alt="Example Image" src="http://example.com/image.png" />')
})

it('should return a markdown image tag for non-retina images', () => {
  const dimensions: ImageDimensions = {width: 200, height: 100, ppi: 96}
  const alt = 'image/png'
  const src = 'http://example.com/image.png'

  const result = markdownImageTag(dimensions, src, alt)
  expect(result).toBe('![image/png](http://example.com/image.png)')
})

it('should return an img tag with default alt text for retina images when alt is not provided', () => {
  const dimensions: ImageDimensions = {width: 200, height: 100, ppi: RETINA_PPI}
  const src = 'http://example.com/image.png'

  const result = markdownImageTag(dimensions, src)
  expect(result).toBe('<img width="100" alt="Image" src="http://example.com/image.png" />')
})

it('should return a markdown image tag with alt text for non-retina images', () => {
  const dimensions: ImageDimensions = {width: 200, height: 100, ppi: 96}
  const src = 'http://example.com/image.png'
  const alt = 'Image example'

  const result = markdownImageTag(dimensions, src, alt)
  expect(result).toBe('![Image example](http://example.com/image.png)')
})
