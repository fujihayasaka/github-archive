import type {FileUploadResult} from '@github-ui/markdown-editor'

export const getDiffLines = (lines: string[], file?: File) => {
  const lastLineIndex = lines.length - 1
  const lastLineContent = lines[lastLineIndex]

  const hasDiffComparator = !!(lastLineContent?.startsWith('+') || lastLineContent?.startsWith('-'))
  const diffLines = {newLines: 1, newStart: lastLineIndex + 1, oldStart: lastLineIndex + 1, oldLines: 1}

  const uploadingText = `![Uploading ${file?.name || ''}...]()`
  const removeLine = `${hasDiffComparator ? '' : '-'}${lastLineContent}`
  const replacedText = `${hasDiffComparator ? '' : '+'}${lastLineContent}`.replace(uploadingText, '')

  return {replacedText, removeLine, lastLineIndex, hasDiffComparator, diffLines, uploadingText}
}

export const getDiffValues = ({
  file,
  editorContent,
  replaceUploadingText = false,
  fileUrl = undefined,
  removeUploadingTextOnly = false,
}: {
  file: File
  editorContent: string[]
  replaceUploadingText?: boolean
  fileUrl?: string
  removeUploadingTextOnly?: boolean
}) => {
  const {replacedText, removeLine, lastLineIndex, hasDiffComparator, diffLines, uploadingText} = getDiffLines(
    editorContent,
    file,
  )

  const markdownContent = file.type.startsWith('video/') ? `++!${fileUrl}` : `![${file.name}](${fileUrl})`

  const addLine = replaceUploadingText
    ? `${replacedText}${!removeUploadingTextOnly ? ` ${markdownContent}` : ''}`
    : `${hasDiffComparator ? '' : '+'}${editorContent[lastLineIndex]} ${uploadingText}`

  return {addLine, removeLine, lastLineIndex, hasDiffComparator, diffLines}
}

export const promptFileUploadFailure = (setFileUploading: (prevState: boolean) => void) => {
  setFileUploading(false)
  alert('File upload failed')
  return {url: '', file: {}} as FileUploadResult
}
