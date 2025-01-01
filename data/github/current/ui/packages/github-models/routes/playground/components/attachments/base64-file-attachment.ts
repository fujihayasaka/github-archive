// NOTE: as we move to uploadable assets, this file will be deleted at some point
//   it is here only for backwards compatibility

import {resource} from '@github-ui/attachments/util/resource'
import type {FileAttachment} from '@github-ui/attachments/types'

export class Base64FileAttachment implements FileAttachment {
  file: File

  constructor(file: File) {
    this.file = file
  }

  // NOTE: We just use a random UUID, to give React something to key for. Useful if we put files in a loop, or to
  // indicate that a React component is the same, and thus its trees can be reused.
  key = globalThis.crypto.randomUUID()

  #resource = resource<string>(async () => {
    return new Promise<string>((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = () => {
        resolve(reader.result as string)
      }
      reader.onerror = reject
      reader.readAsDataURL(this.file)
    })
  })

  prefetch() {
    return this.#resource.load()
  }

  get previewUrl() {
    // NOTE: In the future, if the file is not an image, perhaps we can return a generic preview image
    return this.#resource.read()
  }

  url() {
    return this.#resource.load()
  }
}
