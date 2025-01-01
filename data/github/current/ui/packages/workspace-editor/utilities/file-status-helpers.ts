import type {FileStatus} from '@github-ui/web-commit-dialog'

export function isAdded(fileStatus?: FileStatus) {
  return fileStatus === 'A'
}

export function isModified(fileStatus?: FileStatus) {
  return fileStatus === 'M'
}

export function isDeleted(fileStatus?: FileStatus) {
  return fileStatus === 'D'
}

interface GetFileStatusIconParams {
  // The file path to check
  path: string
  // Local file statuses map
  localFileStatuses: Record<string, FileStatus>
  // PR file statuses map
  prFileStatuses: Record<string, FileStatus>
  // Reference being compared against
  compareRef?: string
  // PR head branch name
  headBranch?: string
}

export function getFileStatus({
  path,
  localFileStatuses,
  prFileStatuses,
  compareRef,
  headBranch,
}: GetFileStatusIconParams) {
  let fileStatus: FileStatus | undefined

  const isDeletedLocally = isDeleted(localFileStatuses[path])
  const isDeletedInPR = isDeleted(prFileStatuses[path])
  const isComparingAgainstHead = compareRef === headBranch
  const isFileInPR = path in prFileStatuses

  if (isDeletedLocally || (!isDeletedInPR && (isComparingAgainstHead || !isFileInPR))) {
    // use local file status when:
    // - the file is deleted locally
    // - the file is not deleted in the PR and either:
    //   - compare is the PR head - this comparison includes local changes only
    //   - the file is not in the PR aka it's a new file
    fileStatus = localFileStatuses[path]
  } else {
    // otherwise use the file status from the PR
    // this means that a PR file with "A" status and "M" status locally will show as "A"
    fileStatus = prFileStatuses[path]
  }

  return fileStatus
}
