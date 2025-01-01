import {fireEvent} from '@testing-library/react'

export function fireFileDropEvent(files: File[], el = document.body) {
  const attachments = files.map(file => ({file}))
  fireEvent(el, new CustomEvent('file-attachment-accept', {detail: {attachments}}))
}
