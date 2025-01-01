// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'
import {useSafeAsyncCallback} from '@github-ui/use-safe-async-callback'
import type {SyntheticChangeEmitter} from '@github-ui/use-synthetic-change'
import type {FileType, UnifiedFileSelectResult} from '@github-ui/use-unified-file-select'
import {useUnifiedFileSelect} from '@github-ui/use-unified-file-select'
import {useCallback, useEffect, useRef, useState} from 'react'

import type {ImageDimensions} from './types'
import {getImageSizeFromFile, markdownComment, markdownImageTag, markdownLink} from './utils'

export type {FileType} from '@github-ui/use-unified-file-select'

const placeholder = (file: File) => markdownComment(`Uploading "${file.name}"...`)

const markdown = (file: File, url: string | null, dimensions?: ImageDimensions | null) => {
  if (!url) return markdownComment(`Failed to upload "${file.name}"`)
  if (file.type.startsWith('video/')) return url
  if (file.type.startsWith('image/')) return markdownImageTag(dimensions || {width: 0, height: 0, ppi: 1}, url, 'Image')
  return markdownLink(file.name, url)
}

type UploadProgress = [current: number, total: number]

type UseFileHandlingResult = UnifiedFileSelectResult & {
  errorMessage?: string
  uploadProgress?: UploadProgress
}

type UseFileHandlingProps = {
  repositoryId?: number
  inputRef: React.RefObject<HTMLTextAreaElement>
  emitChange: SyntheticChangeEmitter
  disabled?: boolean
  value: string
  onUploadFile?: (file: File) => Promise<FileUploadResult>
  acceptedFileTypes?: FileType[]
}

export type FileUploadResult = {
  /** The URL of the uploaded file. `null` if the upoad failed (or reject the promise). */
  url: string
  /**
   * The file that was uploaded. Typically the client-side detected name, size, and content
   * type can be unreliable, so your file upload service may provide more accurate data. By
   * receiving an updated File instance with the more accurate data, the Markdown editor can
   * make better decisions.
   */
  file: File
}

type OptFileUploadResult = FileUploadResult | {url: null; file: File}

const noop = () => {
  /*noop*/
}

export const useFileHandling = ({
  emitChange,
  value,
  inputRef,
  disabled,
  onUploadFile,
  acceptedFileTypes,
}: UseFileHandlingProps): UseFileHandlingResult | null => {
  const [errorMessage, setErrorMessage] = useState<string | undefined>(undefined)

  const errorVisibleForEnoughTime = useRef(false)
  useEffect(() => {
    if (errorMessage) {
      errorVisibleForEnoughTime.current = false
      const id = setTimeout(() => (errorVisibleForEnoughTime.current = true), 1000)
      return () => clearTimeout(id)
    }
  }, [errorMessage])
  useEffect(() => {
    // clears the error message when the user types and enough time has passed
    if (errorVisibleForEnoughTime.current) setErrorMessage(undefined)
  }, [value])

  const safeSetRejectedFiles = useSafeAsyncCallback((files: File[]) => {
    const types = new Set(
      files
        .map(({name}) => {
          const parts = name.split('.')
          return parts.length > 1 ? `.${parts.at(-1)}` : ''
        })
        .filter(s => s !== ''),
    )

    if (types.size > 0) setErrorMessage(`File type${types.size > 1 ? 's' : ''} not allowed: ${[...types].join(', ')}`)
  })

  const [uploadProgress, setUploadProgress] = useState<UploadProgress | undefined>(undefined)
  const safeClearUploadProgress = useSafeAsyncCallback(() => setUploadProgress(undefined))

  const insertPlaceholder = useCallback(
    (files: File[]) => {
      if (!inputRef?.current) return
      const newLinePrefix = getNewlinePrefix(inputRef.current.value, inputRef.current.selectionStart)
      const newLineSuffix = getNewlineSuffix(inputRef.current.value, inputRef.current.selectionEnd)
      const placeholders = `${newLinePrefix}${files.map(placeholder).join('\n')}${newLineSuffix}`

      emitChange(placeholders)
    },
    [inputRef, emitChange],
  )

  const replacePlaceholderWithMarkdown = (file: File, url: string | null, dimensions: ImageDimensions | null) => {
    if (!inputRef?.current) return
    const placeholderStr = placeholder(file)
    const placeholderIndex = inputRef.current.value.indexOf(placeholderStr)
    if (placeholderIndex === -1) return
    emitChange(markdown(file, url, dimensions), [placeholderIndex, placeholderIndex + placeholderStr.length])
  }

  // It's crucial that this is done safely because file uploads can take a long time - there's
  // a very good chance that the references will be outdated or the component unmounted by the time this is called.
  const safeHandleCompletedFileUpload = useSafeAsyncCallback(
    ({file, url}: OptFileUploadResult, dimensions: ImageDimensions | null) => {
      setUploadProgress(progress => progress && [progress[0] + 1, progress[1]])

      replacePlaceholderWithMarkdown(file, url, dimensions)
    },
  )

  const uploadFiles = useCallback(
    (files: File[]): Array<Promise<void>> =>
      files.map(async file => {
        let result: OptFileUploadResult = {url: null, file}
        let dimensions: ImageDimensions | null = null
        try {
          result = (await onUploadFile?.(file)) ?? {file, url: null}
        } catch {
          result = {file, url: null}
        }
        if (result.url) {
          try {
            dimensions = await getImageSizeFromFile(file)
          } catch {
            dimensions = {width: 0, height: 0, ppi: 1}
            reportError('Failed to get image size from file', {
              message: 'Failed to get image size from file',
              reactAppName: 'markdown-editor',
            })
          }
        }

        safeHandleCompletedFileUpload(result, dimensions)
      }),
    [onUploadFile, safeHandleCompletedFileUpload],
  )

  const onSelectFiles = useCallback(
    async (accepted: File[], rejected: File[]) => {
      if (accepted.length > 0) {
        setUploadProgress([1, accepted.length])
        insertPlaceholder(accepted)

        await Promise.all(uploadFiles(accepted))

        safeClearUploadProgress()
      }
      // setting rejected files will hide upload progress, replacing it with an error message
      // so only call it after successful files are uploaded
      safeSetRejectedFiles(rejected)
    },
    [safeSetRejectedFiles, insertPlaceholder, uploadFiles, safeClearUploadProgress],
  )

  let fileSelect = useUnifiedFileSelect({
    acceptedFileTypes,
    multi: true,
    // eslint-disable-next-line @typescript-eslint/no-misused-promises
    onSelect: onSelectFiles,
  })

  if (disabled) {
    fileSelect = {
      clickTargetProps: {
        onClick: noop,
      },
      dropTargetProps: {
        onDragEnter: noop,
        onDragLeave: noop,
        onDrop: noop,
        onDragOver: noop,
      },
      pasteTargetProps: {
        onPaste: noop,
      },
      isDraggedOver: false,
    }
  }

  return onUploadFile ? {...fileSelect, errorMessage, uploadProgress} : null
}

function getNewlinePrefix(input: string, selectionStart: number) {
  // if the cursor is at the beginning of the input, don't add a newline
  if (selectionStart === 0) return ''

  if (input[selectionStart - 1] === '\n') {
    // if the cursor already has two newlines before it, don't add another
    if (selectionStart === 1 || input[selectionStart - 2] === '\n') return ''
  }

  const previousNewlineIndex = input.lastIndexOf('\n', selectionStart - 1)
  // if there are non-whitespace characters on the current line, add two newlines
  if (/\S/.test(input.substring(previousNewlineIndex, selectionStart))) {
    return '\n\n'
  }

  // if the current line is empty, add one newline
  return '\n'
}

function getNewlineSuffix(input: string, selectionEnd: number) {
  // if the cursor is at the end of the input, don't add a newline
  if (input.length === selectionEnd) return ''

  if (input[selectionEnd] === '\n') {
    // if the cursor already has two newlines after it, don't add another
    if (selectionEnd === input.length - 1 || input[selectionEnd + 1] === '\n') return ''
  }

  const nextNewlineIndex = input.indexOf('\n', selectionEnd)
  // if there are non-whitespace characters on the current line, add two newlines
  if (/\S/.test(input.substring(selectionEnd, nextNewlineIndex))) {
    return '\n\n'
  }

  // if the current line is empty, add one newline
  return '\n'
}
