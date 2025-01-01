import {isMacOS} from '@github-ui/get-os'

import {PNGScanner} from './pngScanner'
import type {ImageDimensions} from './types'

export const getSelectedLineRange = (textarea: HTMLTextAreaElement): [number, number] => {
  // Subtract one from the caret position so the newline found is not the one _at_ the caret position
  // then add one because we don't want to include the found newline. Also changes -1 (not found) result to 0
  const start = textarea.value.lastIndexOf('\n', textarea.selectionStart - 1) + 1

  // activeLineEnd will be the index of the next newline inclusive, which works because slice is last-index exclusive
  let end = textarea.value.indexOf('\n', textarea.selectionEnd)
  if (end === -1) end = textarea.value.length

  return [start, end]
}

export const markdownComment = (text: string) => `<!-- ${text.replaceAll('--', '\\-\\-')} -->`

export const markdownLink = (text: string, url: string) =>
  `[${text.replaceAll('[', '\\[').replaceAll(']', '\\]')}](${url.replaceAll('(', '\\(').replaceAll(')', '\\)')})`

export const isModifierKey = (event: KeyboardEvent | React.KeyboardEvent<unknown>) =>
  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
  isMacOS() ? event.metaKey : event.ctrlKey

const METERS_PER_INCH = 0.0254
const RETINA_PPI = 72 * 2

const getImageDimensions = (imgData: ArrayBuffer) => {
  const scanner = new PNGScanner(imgData)

  const meta = {
    width: 0,
    height: 0,
    ppi: 1,
  }

  scanner.scan(function (this: PNGScanner, type) {
    switch (type) {
      case 'IHDR': {
        meta.width = this.readLong()
        meta.height = this.readLong()
        return true
      }
      case 'pHYs': {
        const ppuX = this.readLong()
        const ppuY = this.readLong()
        const unit = this.readChar()
        let inchesRatio
        if (unit === 1) {
          inchesRatio = METERS_PER_INCH
        }
        if (inchesRatio) {
          meta.ppi = Math.round(((ppuX + ppuY) / 2) * inchesRatio)
        }
        return false
      }
      case 'IDAT': {
        return false
      }
    }

    return true
  })

  return meta
}

export const getImageSizeFromFile = async (file: File) => {
  const imgResult = await new Promise<ArrayBuffer>((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(reader.result as ArrayBuffer)
    // eslint-disable-next-line @typescript-eslint/prefer-promise-reject-errors
    reader.onerror = () => reject(reader.error)
    reader.readAsArrayBuffer(file)
  })
  return imgResult ? getImageDimensions(imgResult) : null
}

export const markdownImageTag = (dimensions: ImageDimensions, src: string, alt: string = 'Image') => {
  if (dimensions.ppi === RETINA_PPI) {
    const width = Math.round(dimensions.width / 2)
    // eslint-disable-next-line github/unescaped-html-literal
    return `<img width="${width}" alt="${alt}" src="${src}" />`
  }
  return `![${alt}](${src})`
}
