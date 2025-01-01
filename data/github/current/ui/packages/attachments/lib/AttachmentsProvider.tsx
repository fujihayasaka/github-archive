import React from 'react'
import invariant from 'tiny-invariant'

import type {Attachment, FileAttachment} from './types'
import {useSubscribedHandles} from './use-subscribed-handles'

type AttachmentState = {
  attachments: Attachment[]
  errorMessage?: string
}

type AttachmentAPI = {
  addFiles(files: FileAttachment[]): void
  remove(attachment: Attachment): void
  reset(): void
}

export type AttachmentsContext = [
  state: AttachmentState & {attachLimit: number; acceptedMIME: string[]},
  api: AttachmentAPI,
]

const eventSingleton = new EventTarget()
const attachmentContext = React.createContext<AttachmentsContext | null>(null)

const ONE_MB = 1 * 1024 * 1024 // 1MB

export function AttachmentsProvider(
  props: React.PropsWithChildren<{
    attachLimit?: number
    acceptedMIME?: string
    fileSizeLimit?: number
    subscribed?: boolean
  }>,
) {
  const attachLimit = props.attachLimit ?? 1
  const acceptedMIME = React.useMemo(() => props.acceptedMIME?.split(',') ?? ['image/*'], [props.acceptedMIME])
  const acceptedMIMERegex = React.useMemo(
    () => acceptedMIME.map(type => new RegExp(type.replace(/\*/g, '.*'))),
    [acceptedMIME],
  )
  const fileSizeLimit = React.useMemo(() => props.fileSizeLimit ?? ONE_MB, [props.fileSizeLimit])

  type Actions =
    | {type: 'new_files'; files: FileAttachment[]}
    | {type: 'remove'; attachment: Attachment}
    | {type: 'reset'}
  const [state, dispatch] = React.useReducer(
    (prevState: AttachmentState, action: Actions): AttachmentState => {
      switch (action.type) {
        case 'new_files': {
          if (action.files.length === 0) return prevState

          const files = filterUnsupportedFiles(
            action.files.map(f => f.file),
            acceptedMIMERegex,
          )
          if (files.length === 0)
            return {errorMessage: "Sorry, it look's like that file was not supported.", attachments: []}
          if (areFilesTooLarge(files, fileSizeLimit))
            return {
              errorMessage: `Sorry, we only support files up to ${formatFileSize(fileSizeLimit)}.`,
              attachments: [],
            }

          if (files.length > attachLimit) {
            return {
              errorMessage: `Sorry, only up to ${pluralize('file', attachLimit)} per message are supported.`,
              attachments: [],
            }
          }
          return {attachments: action.files}
        }
        case 'remove':
          return {attachments: prevState.attachments.filter(a => a !== action.attachment)}
        case 'reset':
        default:
          return {attachments: []}
      }
    },
    {attachments: []},
  )

  // The public api
  const api = useSubscribedHandles<AttachmentAPI>(
    eventSingleton,
    {
      addFiles(files) {
        dispatch({type: 'new_files', files})
      },
      remove(attachment) {
        dispatch({type: 'remove', attachment})
      },
      reset() {
        dispatch({type: 'reset'})
      },
    },
    props.subscribed,
  )

  const value = React.useMemo<AttachmentsContext>(
    () => [
      {
        attachments: state.attachments,
        errorMessage: state.errorMessage,
        attachLimit,
        acceptedMIME,
      },
      api,
    ],
    [state, api, attachLimit, acceptedMIME],
  )
  return <attachmentContext.Provider value={value}>{props.children}</attachmentContext.Provider>
}

export function useAttachments() {
  const context = React.useContext(attachmentContext)
  invariant(context, 'Expected a AttachmentsProvider')
  return context
}

function filterUnsupportedFiles(files: File[], acceptedMIMESRegex: RegExp[]): File[] {
  return files.filter(file => acceptedMIMESRegex.some(type => file.type.match(type)))
}

function areFilesTooLarge(files: File[], fileSizeLimit: number): boolean {
  return files.some(file => file.size > fileSizeLimit)
}

function pluralize(word: string, count: number) {
  return `${count} ${word}${count > 1 ? 's' : ''}`
}

function formatFileSize(size: number) {
  const MB = 1024 * 1024
  const KB = 1024

  if (size >= MB) {
    return `${(size / MB).toFixed(2)}MB`
  }
  return `${Math.round(size / KB)}KB`
}
