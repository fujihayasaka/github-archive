export interface Attachment {
  key: string

  url(): Promise<string>
  previewUrl: string

  prefetch(): Promise<unknown>
}

export interface FileAttachment extends Attachment {
  file: File
}
