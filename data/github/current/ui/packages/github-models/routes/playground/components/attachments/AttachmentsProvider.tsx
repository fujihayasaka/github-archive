import type {Attachment} from '@github/file-attachment-element'
import React from 'react'

import invariant from 'tiny-invariant'
import {usePlaygroundState} from '../../../../contexts/PlaygroundStateContext'
import {pluralize} from '../../../../utils/pluralize'
import {ACCEPTED_MIME_REGEX, MAX_ATTACHMENT_COUNT, MAX_ATTACHMENT_SIZE} from './constants'
import type {FileReference} from './file-reference'
import {useSubscribedHandles} from './use-subscribed-handles'

declare global {
  interface HTMLElementEventMap {
    'file-attachment-accept': CustomEvent<{attachments: Attachment[]}>
  }
}

type AttachmentState = {
  attachments: FileReference[]
  errorMessage?: string
}

type AttachmentAPI = {
  addFiles(files: FileReference[]): void
  removeFile(attachment: FileReference): void
  reset(): void
}

type AttachmentsContext = [state: AttachmentState, api: AttachmentAPI]

const eventSingleton = new EventTarget()
const attachmentContext = React.createContext<AttachmentsContext | null>(null)

export function AttachmentsProvider(props: React.PropsWithChildren) {
  const playgroundState = usePlaygroundState()
  const {models: modelStates, syncInputs} = playgroundState

  type Actions = {type: 'new_files'; files: FileReference[]} | {type: 'remove'; file: FileReference} | {type: 'reset'}
  const [state, dispatch] = React.useReducer(
    (prevState: AttachmentState, action: Actions): AttachmentState => {
      switch (action.type) {
        case 'new_files': {
          if (action.files.length === 0) return prevState

          const files = filterUnsupportedFiles(action.files.map(f => f.file))
          if (files.length === 0)
            return {errorMessage: "Sorry, it look's like that file was not supported.", attachments: []}
          if (areFilesTooLarge(files)) return {errorMessage: 'Sorry, we only support files up to 1MB.', attachments: []}

          if (files.length > MAX_ATTACHMENT_COUNT)
            return {
              errorMessage: `Sorry, we only support ${pluralize('file', MAX_ATTACHMENT_COUNT)} right now.`,
              attachments: [],
            }

          const maxImagePerTurn = Math.min(
            ...modelStates.map(
              modelState => modelState.modelInputSchema?.capabilities?.chat?.imagesPerTurn || MAX_ATTACHMENT_COUNT,
            ),
          )

          if (files.length > maxImagePerTurn) {
            if (modelStates.length > 1) {
              // Comparison view
              return {
                errorMessage: `Sorry, at least one of the models only supports up to ${pluralize(
                  'file',
                  maxImagePerTurn,
                )} per message.`,

                attachments: [],
              }
            } else {
              return {
                errorMessage: `Sorry, the model only supports up to ${pluralize('file', maxImagePerTurn)} per message.`,
                attachments: [],
              }
            }
          }
          return {attachments: action.files}
        }
        case 'remove':
          return {attachments: prevState.attachments.filter(a => a !== action.file)}
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
      removeFile(file) {
        dispatch({type: 'remove', file})
      },
      reset() {
        dispatch({type: 'reset'})
      },
    },
    syncInputs,
  )

  const value = React.useMemo<AttachmentsContext>(() => [state, api], [state, api])
  return <attachmentContext.Provider value={value}>{props.children}</attachmentContext.Provider>
}

export function useChatAttachments() {
  const context = React.useContext(attachmentContext)
  invariant(context, 'Expected a AttachmentsProvider')
  return context
}

function filterUnsupportedFiles(files: File[]): File[] {
  return files.filter(file => ACCEPTED_MIME_REGEX.some(type => file.type.match(type)))
}

function areFilesTooLarge(files: File[]): boolean {
  return files.some(file => file.size > MAX_ATTACHMENT_SIZE)
}
