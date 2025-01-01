// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {noop} from '@github-ui/noop'
import {FileFilter, type FileFilterProps} from '../../components/diff-filtering/FileFilter'

export const defaultMockFileFilterProps = getMockFileFilterPageData()

export function TestFileFilterComponent(props: FileFilterProps) {
  return <FileFilter {...props} />
}

export function getMockFileFilterPageData(): FileFilterProps {
  return {
    basePath: '/test-user/test-repo/pull/1',
    fileFilterMenuOptions: {
      canSeeCodeownersFilter: false,
      canSeeDeletedFilesFilter: true,
      canSeeOnlyManifestFilesFilter: false,
      canSeeVendorFilesFilter: false,
    },
    fileFilterState: {
      fileExtensions: {},
      filterText: '',
      showDeletedFiles: true,
      showOnlyManifestFiles: false,
      showOnlyOwnedFiles: false,
      showVendoredFiles: true,
      showViewedFiles: true,
      unselectedFileExtensions: new Set<string>(),
    },
    setFileFilterState: noop,
  }
}
