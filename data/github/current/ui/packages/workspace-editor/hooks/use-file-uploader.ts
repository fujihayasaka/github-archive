import {REPOLESS_ACCEPTED_FILE_TYPES, useUploadFile} from '@github-ui/comment-box/fileUpload'
import {useFileHandling} from '@github-ui/markdown-editor'
import type {KeyboardEvent, MouseEvent, RefObject} from 'react'
import {useCallback, useEffect} from 'react'

import {useFilesContext} from '../contexts/FilesContext'
import {useAnalytics} from '../telemetry/use-analytics'
import {getDiffLines, getDiffValues, promptFileUploadFailure} from '../utilities/file-uploader-helpers'

export const useFileUploader = ({
  fileUploading,
  repositoryId,
  blobContents,
  currentBlobContents,
  currentPath,
  setFileUploading,
}: {
  repositoryId: number
  blobContents: string | undefined
  currentBlobContents: string
  currentPath: string
  fileUploading: boolean
  setFileUploading: (fileUploading: boolean) => void
}) => {
  const sendEvent = useAnalytics()
  const {getCurrentFileContent, applyFileToContent} = useFilesContext()

  const uploadFile = useUploadFile(repositoryId.toString())

  const getEditorContent = useCallback(
    (current: string) => {
      const {content} = getCurrentFileContent(currentPath, current)
      return content?.split('\n')
    },
    [currentPath, getCurrentFileContent],
  )

  const updateFile = useCallback(
    ({
      diffLines,
      removeLine,
      addLine,
      currentEditorContents,
    }: {
      diffLines: {newLines: number; newStart: number; oldStart: number; oldLines: number}
      removeLine: string
      addLine: string
      currentEditorContents: string
    }) => {
      return applyFileToContent(
        [
          {
            filePath: currentPath,
            diff: {
              ...diffLines,
              lines: [removeLine, addLine],
            },
            eofContent: addLine.slice(1),
          },
        ],
        [{path: currentPath, blobContents: currentEditorContents}],
      )
    },
    [applyFileToContent, currentPath],
  )

  const handleNewLineFormatting = useCallback(() => {
    const current = currentBlobContents
    const editorContent = getEditorContent(current) || []

    const {removeLine, lastLineIndex, hasDiffComparator, diffLines} = getDiffLines(editorContent)

    const lineWithNewLineToAttachmentMarkdown = `${hasDiffComparator ? '' : '+'}${editorContent[lastLineIndex]
      ?.replace(/\s*![[^)]/g, '\n![')
      ?.replace(/\s\+\+!/g, '\n')}`

    updateFile({diffLines, removeLine, addLine: lineWithNewLineToAttachmentMarkdown, currentEditorContents: current})
  }, [currentBlobContents, getEditorContent, updateFile])

  const applyChangeToEditor = async (file: File) => {
    setFileUploading(true)

    const current = currentBlobContents
    const editorContent = getEditorContent(current)

    if (!editorContent) {
      return promptFileUploadFailure(setFileUploading)
    }

    const {addLine, removeLine, diffLines} = getDiffValues({file, editorContent})

    try {
      updateFile({removeLine, addLine, diffLines, currentEditorContents: current})

      const fileMetadata = await uploadFile(file)
      const updatedEditorContent = getEditorContent(current)
      const updatedFile = fileMetadata.file

      if (!updatedEditorContent) {
        return promptFileUploadFailure(setFileUploading)
      }

      const {removeLine: updatedRemoveLine, addLine: updatedAddLine} = getDiffValues({
        file: updatedFile,
        editorContent: updatedEditorContent,
        replaceUploadingText: true,
        fileUrl: fileMetadata.url,
      })

      const newFileWithUploadedAttachment = updateFile({
        removeLine: updatedRemoveLine,
        addLine: updatedAddLine,
        diffLines,
        currentEditorContents: current,
      })

      sendEvent('editor.file-edit', {
        file_extension: fileMetadata.file.type,
      })

      if (!newFileWithUploadedAttachment[currentPath]) alert('File upload failed')

      return fileMetadata
    } catch {
      const updatedEditorContent = getEditorContent(current)

      if (!updatedEditorContent) {
        return promptFileUploadFailure(setFileUploading)
      }

      const {removeLine: updatedRemoveLine, addLine: updatedAddLine} = getDiffValues({
        file,
        editorContent: updatedEditorContent,
        replaceUploadingText: true,
        removeUploadingTextOnly: true,
      })

      updateFile({removeLine: updatedRemoveLine, addLine: updatedAddLine, diffLines, currentEditorContents: current})
      return promptFileUploadFailure(setFileUploading)
    }
  }

  const fileHandler = useFileHandling({
    value: blobContents || '',
    disabled: false,
    onUploadFile: applyChangeToEditor,
    acceptedFileTypes: REPOLESS_ACCEPTED_FILE_TYPES,
    emitChange: () => {},
    inputRef: {} as RefObject<HTMLTextAreaElement>,
  })

  const onFileUpload = (event: MouseEvent | KeyboardEvent) => {
    if (!fileHandler) return

    fileHandler.clickTargetProps?.onClick(event as MouseEvent)
    event.preventDefault()
  }

  useEffect(() => {
    if (fileUploading && !fileHandler?.uploadProgress) handleNewLineFormatting()

    setFileUploading(!!fileHandler?.uploadProgress)
  }, [fileHandler?.uploadProgress, fileUploading, handleNewLineFormatting, setFileUploading])

  return {onFileUpload, fileHandler}
}
