import {forwardRef, useCallback, useImperativeHandle, useRef} from 'react'
import {usePromptCompareManager} from '../prompt-compare-manager'
import {parseJSONL, parseCSV} from '../utils/import-utils'

export type ImportRowsProps = {
  setImportError: (error: string[]) => void
}

// eslint-disable-next-line react/display-name
export const ImportRows = forwardRef<{triggerImport: () => void}, ImportRowsProps>(({setImportError}, ref) => {
  const manager = usePromptCompareManager()
  const datasetInputRef = useRef<HTMLInputElement>(null)
  const ACCEPTED_MIME = [
    '.jsonl',
    'text/jsonl',
    'application/json-lines',
    'application/jsonl',
    '.csv',
    'text/csv',
    'application/csv',
  ]
  const errors: string[] = []

  const triggerImport = useCallback(() => {
    datasetInputRef.current?.click()
  }, [])

  useImperativeHandle(
    ref,
    () => ({
      triggerImport,
    }),
    [triggerImport],
  )

  return (
    <>
      <input
        ref={datasetInputRef}
        type="file"
        accept={ACCEPTED_MIME.join(',')}
        multiple={false}
        hidden
        onChange={async e => {
          const file = e.target?.files && e.target.files[0]
          if (!file) {
            return
          }

          // Read file
          const content = await new Promise<string>((resolve, reject) => {
            const reader = new FileReader()
            reader.onload = () => {
              resolve(reader.result as string)
            }
            reader.onerror = reject
            reader.readAsText(file)
          })

          // Split content into lines
          let lines = content.split('\n')

          // limit to lines to first 100
          if (lines.length > 100) {
            lines = lines.slice(0, 100)
            errors.push('There is a limit of first 100 rows being imported.')
          }

          if (file.name.endsWith('.jsonl')) {
            await parseJSONL(lines, errors, manager)
          } else if (file.name.endsWith('.csv')) {
            await parseCSV(lines, errors, manager)
          } else {
            errors.push('File type not supported.')
          }

          // ensure elements in errors are unique
          const uniqueErrors = Array.from(new Set(errors))
          setImportError(uniqueErrors)
          // Reset file input
          e.target.value = ''
        }}
      />
    </>
  )
})
