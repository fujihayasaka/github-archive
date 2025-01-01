import {debounce} from '@github/mini-throttle'
import {FileFilterShared, type FileFilterBaseProps} from '@github-ui/diff-file-tree/file-filter'
import {useMemo, useRef} from 'react'
import {ActionList} from '@primer/react'
import type {FileFilterState} from '../hooks/use-file-filtering'
import type {PullRequestFileTreeDiff} from '../page-data/payloads/file-tree'

export type FileFilterProps = {
  diffs: Readonly<Array<Readonly<PullRequestFileTreeDiff>>>
  fileFilterState: FileFilterState
  setFileFilterState: (state: FileFilterState) => void
} & Omit<FileFilterBaseProps, 'onFilterChange'>

export function FileFilter({diffs, fileFilterState, setFileFilterState}: FileFilterProps) {
  const {
    filterText,
    fileExtensions,
    unselectedFileExtensions,
    showCodeowners,
    showDeletedFiles,
    showOnlyManifestFiles,
    showVendorFiles,
    showViewedFiles,
  } = fileFilterState

  const debouncedOnSearch = useRef(
    debounce(
      (newQuery: string) =>
        setFileFilterState({
          ...fileFilterState,
          filterText: newQuery,
        }),
      250,
    ),
  )

  const onFilterChange = (
    type: 'selectFileExtension' | 'unselectFileExtension',
    payload: {
      extension: string
    },
  ) => {
    setFileFilterState({
      ...fileFilterState,
      unselectedFileExtensions: new Set(
        type === 'selectFileExtension'
          ? [...unselectedFileExtensions].filter(ext => ext !== payload.extension)
          : [...unselectedFileExtensions, payload.extension],
      ),
    })
  }

  const {showCodeownersFilter, showDeletedFilesFilter, showOnlyManifestFilesFilter, showVendorFilesFilter} = useMemo(
    () => ({
      showCodeownersFilter: diffs.some(diff => diff.isCodeowner),
      showDeletedFilesFilter: diffs.some(diff => diff.changeType === 'REMOVED' || diff.changeType === 'DELETED'),
      showOnlyManifestFilesFilter: diffs.some(diff => diff.isManifestFile),
      showVendorFilesFilter: diffs.some(diff => diff.isVendored),
    }),
    [diffs],
  )

  return (
    <FileFilterShared
      filterText={filterText}
      fileExtensions={fileExtensions}
      unselectedFileExtensions={unselectedFileExtensions}
      onFilterTextChange={text => debouncedOnSearch.current(text)}
      onFilterChange={onFilterChange}
      additionalFilterGroups={
        <>
          {showCodeownersFilter && (
            <>
              <ActionList.Divider />
              <ActionList.Group selectionVariant="single">
                <ActionList.Item
                  selected={showCodeowners}
                  onSelect={() => {
                    setFileFilterState({
                      ...fileFilterState,
                      showCodeowners: !showCodeowners,
                    })
                  }}
                >
                  Only files owned by you
                </ActionList.Item>
              </ActionList.Group>
            </>
          )}
          <ActionList.Divider />
          <ActionList.Group selectionVariant="single">
            {showOnlyManifestFilesFilter && (
              <ActionList.Item
                selected={showOnlyManifestFiles}
                onSelect={() => setFileFilterState({...fileFilterState, showOnlyManifestFiles: !showOnlyManifestFiles})}
              >
                Only manifest files
              </ActionList.Item>
            )}
            {showDeletedFilesFilter && (
              <ActionList.Item
                selected={showDeletedFiles}
                onSelect={() => setFileFilterState({...fileFilterState, showDeletedFiles: !showDeletedFiles})}
              >
                Deleted files
              </ActionList.Item>
            )}
            {showVendorFilesFilter && (
              <ActionList.Item
                selected={showVendorFiles}
                onSelect={() => setFileFilterState({...fileFilterState, showVendorFiles: !showVendorFiles})}
              >
                Vendored files
              </ActionList.Item>
            )}
            <ActionList.Item
              selected={showViewedFiles}
              onSelect={() => {
                setFileFilterState({
                  ...fileFilterState,
                  showViewedFiles: !showViewedFiles,
                })
              }}
            >
              Viewed files
            </ActionList.Item>
          </ActionList.Group>
        </>
      }
    />
  )
}
