import {debounce} from '@github/mini-throttle'
import {FileFilterShared, type FileFilterBaseProps} from '@github-ui/diff-file-tree/file-filter'
import {useRef} from 'react'
import {ActionList} from '@primer/react'
import {useSearchParams} from '@github-ui/use-navigate'
import {updateSearchParams} from '@github-ui/history'
import {useCodeowners} from '../../page-data/loaders/use-codeowners-data'

export type FileFilterState = {
  filterText: string
  fileExtensions: Record<string, number>
  unselectedFileExtensions: Set<string>
  showDeletedFiles?: boolean
  showOnlyManifestFiles?: boolean
  showOnlyOwnedFiles?: boolean
  showVendoredFiles?: boolean
  showViewedFiles?: boolean
}

export type FileFilterMenuOptions = {
  canSeeCodeownersFilter: boolean
  canSeeDeletedFilesFilter: boolean
  canSeeOnlyManifestFilesFilter: boolean
  canSeeVendorFilesFilter: boolean
}

export type FileFilterProps = {
  basePath: string
  fileFilterMenuOptions: FileFilterMenuOptions
  fileFilterState: FileFilterState
  viewerLogin?: string
  setFileFilterState: (state: FileFilterState) => void
  setUserHasInteracted?: (state: boolean) => void
} & Omit<FileFilterBaseProps, 'onFilterChange'>

export function FileFilter({
  basePath,
  fileFilterMenuOptions,
  fileFilterState,
  filterSize,
  viewerLogin,
  setFileFilterState,
  setUserHasInteracted,
}: FileFilterProps) {
  const [searchParams] = useSearchParams()
  const {data: codeownersData} = useCodeowners({basePath})

  const {
    filterText,
    fileExtensions,
    unselectedFileExtensions,
    showOnlyOwnedFiles,
    showDeletedFiles,
    showOnlyManifestFiles,
    showVendoredFiles,
    showViewedFiles,
  } = fileFilterState

  const {canSeeDeletedFilesFilter, canSeeOnlyManifestFilesFilter, canSeeVendorFilesFilter} = fileFilterMenuOptions

  let {canSeeCodeownersFilter} = fileFilterMenuOptions
  let fileCountOwnedByViewer = 0
  if (codeownersData) {
    canSeeCodeownersFilter = codeownersData.isViewerOneOfMultipleCodeowners
    fileCountOwnedByViewer = Object.values(codeownersData.ownershipByPath).filter(diff => diff.isOwnedByViewer).length
  }

  const debouncedOnSearch = useRef(debounce((newQuery: string) => onFilterChange({filterText: newQuery}), 250))

  const onFileExtensionChange = (
    type: 'selectFileExtension' | 'unselectFileExtension',
    payload: {
      extension: string
    },
  ) => {
    let newUnselectedFileExtensions = unselectedFileExtensions

    if (type === 'selectFileExtension') {
      newUnselectedFileExtensions = new Set([...unselectedFileExtensions].filter(ext => ext !== payload.extension))
    } else if (type === 'unselectFileExtension') {
      newUnselectedFileExtensions = new Set([...unselectedFileExtensions, payload.extension])
    }

    const allFileExtensions = Object.keys(fileExtensions)
    const selectedFileExtensions = allFileExtensions.filter(extension => !newUnselectedFileExtensions.has(extension))

    // Clean slate
    const newSearchParams = new URLSearchParams(searchParams)
    newSearchParams.delete('file-filters[]')
    // Add selected file extensions
    selectedFileExtensions.map(extension => {
      newSearchParams.append('file-filters[]', extension)
    })

    onFilterChange({unselectedFileExtensions: newUnselectedFileExtensions}, newSearchParams)
  }

  const onFilterChange = (
    changedFileFilterState: {[key: string]: Set<string> | boolean | string},
    newSearchParams?: URLSearchParams,
  ) => {
    if (newSearchParams) {
      updateSearchParams(newSearchParams)
    }
    setFileFilterState({
      ...fileFilterState,
      ...changedFileFilterState,
    })
    setUserHasInteracted?.(true)
  }

  return (
    <FileFilterShared
      filterSize={filterSize}
      filterText={filterText}
      fileExtensions={fileExtensions}
      unselectedFileExtensions={unselectedFileExtensions}
      onFilterTextChange={text => debouncedOnSearch.current(text)}
      onFilterChange={onFileExtensionChange}
      additionalFilterGroups={
        <>
          {canSeeCodeownersFilter && (
            <>
              <ActionList.Divider />
              <ActionList.Group selectionVariant="single">
                <ActionList.Item
                  selected={showOnlyOwnedFiles}
                  onSelect={() => {
                    // This option shouldn't be available if there's no current viewer,
                    // but if we do somehow end up here, do nothing.
                    if (!viewerLogin) return

                    const newSearchParams = new URLSearchParams(searchParams)

                    if (showOnlyOwnedFiles) {
                      newSearchParams.delete('owned-by[]', viewerLogin)
                    } else {
                      newSearchParams.set('owned-by[]', viewerLogin)
                    }
                    onFilterChange({showOnlyOwnedFiles: !showOnlyOwnedFiles}, newSearchParams)
                  }}
                >
                  {`Only files owned by you (${fileCountOwnedByViewer})`}
                </ActionList.Item>
              </ActionList.Group>
            </>
          )}
          <ActionList.Divider />
          <ActionList.Group aria-label="More" selectionVariant="multiple">
            {canSeeOnlyManifestFilesFilter && (
              <ActionList.Item
                selected={showOnlyManifestFiles}
                onSelect={() => {
                  const newSearchParams = new URLSearchParams(searchParams)
                  newSearchParams.set('manifests', `${!showOnlyManifestFiles}`)
                  onFilterChange({showOnlyManifestFiles: !showOnlyManifestFiles}, newSearchParams)
                }}
              >
                Only manifest files
              </ActionList.Item>
            )}
            {canSeeDeletedFilesFilter && (
              <ActionList.Item
                selected={showDeletedFiles}
                onSelect={() => {
                  const newSearchParams = new URLSearchParams(searchParams)
                  newSearchParams.set('show-deleted-files', `${!showDeletedFiles}`)
                  onFilterChange({showDeletedFiles: !showDeletedFiles}, newSearchParams)
                }}
              >
                Deleted files
              </ActionList.Item>
            )}
            {canSeeVendorFilesFilter && (
              <ActionList.Item
                selected={showVendoredFiles}
                onSelect={() => {
                  const newSearchParams = new URLSearchParams(searchParams)
                  newSearchParams.set('show-vendored-files', `${!showVendoredFiles}`)
                  onFilterChange({showVendoredFiles: !showVendoredFiles}, newSearchParams)
                }}
              >
                Vendored files
              </ActionList.Item>
            )}
            <ActionList.Item
              selected={showViewedFiles}
              onSelect={() => {
                const newSearchParams = new URLSearchParams(searchParams)
                newSearchParams.set('show-viewed-files', `${!showViewedFiles}`)
                onFilterChange({showViewedFiles: !showViewedFiles}, newSearchParams)
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
