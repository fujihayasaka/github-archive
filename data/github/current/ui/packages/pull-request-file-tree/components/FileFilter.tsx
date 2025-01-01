import {debounce} from '@github/mini-throttle'
import {FileFilterShared, type FileFilterBaseProps} from '@github-ui/diff-file-tree/file-filter'
import {useRef} from 'react'

export type FileFilterProps = {
  onFilterTextChange(filterText: string): void
  onFileExtensionsChange(type: 'selectFileExtension' | 'unselectFileExtension', extension: string): void
} & Omit<FileFilterBaseProps, 'onFilterChange'>

export function FileFilter({
  filterText,
  onFilterTextChange,
  fileExtensions,
  unselectedFileExtensions,
  onFileExtensionsChange,
}: FileFilterProps) {
  const debouncedOnSearch = useRef(debounce((newQuery: string) => onFilterTextChange(newQuery), 250))

  const onFilterChange = (
    type: 'selectFileExtension' | 'unselectFileExtension',
    payload: {
      extension: string
    },
  ) => {
    onFileExtensionsChange(type, payload.extension)
  }

  return (
    <FileFilterShared
      filterText={filterText}
      fileExtensions={fileExtensions}
      unselectedFileExtensions={unselectedFileExtensions}
      onFilterTextChange={text => debouncedOnSearch.current(text)}
      onFilterChange={onFilterChange}
    />
  )
}
