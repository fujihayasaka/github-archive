import type {FileAttachment} from './types'
import type {UploadPolicy} from './uploadable-assets'

export function testFile(name = 'file.jpg', type = 'image/jpg', size?: number) {
  const file = new File([new ArrayBuffer(1)], name, {
    type,
  })
  if (size) {
    Object.defineProperty(file, 'size', {value: size})
  }
  return file
}

export function mockFileAttachment(file = testFile()) {
  return new MockFileAttachment(file)
}

export class MockFileAttachment implements FileAttachment {
  file: File
  key = 'key'
  constructor(file: File) {
    this.file = file
  }
  async prefetch() {
    return 'prefetch'
  }
  previewUrl = 'preview'
  async url() {
    return 'url'
  }
}

export function mockPolicy() {
  return {
    asset: {
      href: 'ASSET_HREF',
      id: 123,
    },
    asset_upload_url: 'ASSET_UPLOAD_URL',
    form: {
      FORM_KEY: 'FORM_VALUE',
    },
    header: {
      HEADER_KEY: 'HEADER_VALUE',
    },
    same_origin: true,
    upload_url: 'UPLOAD_URL',
  } satisfies UploadPolicy
}
