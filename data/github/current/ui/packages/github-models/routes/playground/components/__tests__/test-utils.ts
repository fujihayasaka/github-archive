import {fireEvent} from '@testing-library/react'

export function testFile(name = 'file.jpg', type = 'image/jpg', size?: number) {
  const file = new File([new ArrayBuffer(1)], name, {
    type,
  })
  if (size) {
    Object.defineProperty(file, 'size', {value: size})
  }
  return file
}

export function fireFileDropEvent(files: File[], el = document.body) {
  const attachments = files.map(file => ({file}))
  fireEvent(el, new CustomEvent('file-attachment-accept', {detail: {attachments}}))
}
