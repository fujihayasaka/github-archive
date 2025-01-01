export type PreviewableContentTypes = 'file' | 'issue'

export type PreviewableContentBase = {
  messageId: string
  name: string
  path: string
  type: PreviewableContentTypes
}

export type File = PreviewableContentBase & {
  language: string
  value: string
  type: 'file'
}

export type Issue = PreviewableContentBase & {
  number: number
  owner: string
  repo: string
  type: 'issue'
}

export type PreviewableContent = File | Issue
