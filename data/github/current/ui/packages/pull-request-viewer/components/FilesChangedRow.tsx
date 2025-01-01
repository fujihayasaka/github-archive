import {FilesChangedRow as CommonFilesChangedRow} from '@github-ui/files-changed-list/FilesChangedRow'
import {graphql, useFragment} from 'react-relay'

import type {FilesChangedRow_pullRequestSummaryDelta$key} from './__generated__/FilesChangedRow_pullRequestSummaryDelta.graphql'

export function FilesChangedRow({
  file,
  pullRequestPath,
}: {
  file: FilesChangedRow_pullRequestSummaryDelta$key
  pullRequestPath: string
}) {
  const fileData = useFragment(
    graphql`
      fragment FilesChangedRow_pullRequestSummaryDelta on PullRequestSummaryDelta {
        additions
        changeType
        deletions
        path
        pathDigest
        unresolvedCommentCount
      }
    `,
    file,
  )

  const pathDigest = fileData.pathDigest
  const filePathUrl = `${pullRequestPath}/files#diff-${pathDigest}`

  return (
    <CommonFilesChangedRow
      additions={fileData.additions}
      changeType={fileData.changeType}
      deletions={fileData.deletions}
      filePathUrl={filePathUrl}
      path={fileData.path}
      unresolvedCommentCount={fileData.unresolvedCommentCount}
    />
  )
}
