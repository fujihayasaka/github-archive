import {FilesChangedList} from '@github-ui/files-changed-list'
import {graphql, useFragment} from 'react-relay'
import type {FragmentRefs} from 'relay-runtime'

import type {FilesChangedListing_pullRequest$key} from './__generated__/FilesChangedListing_pullRequest.graphql'
import {FilesChangedRow} from './FilesChangedRow'

type FilesData = {
  readonly path: string
  readonly ' $fragmentSpreads': FragmentRefs<'FilesChangedRow_pullRequestSummaryDelta'>
}

export function FilesChangedListing({pullRequest}: {pullRequest: FilesChangedListing_pullRequest$key}) {
  const data = useFragment(
    graphql`
      fragment FilesChangedListing_pullRequest on PullRequest {
        comparison(endOid: $endOid, startOid: $startOid) {
          linesAdded
          linesDeleted
          summary {
            path
            ...FilesChangedRow_pullRequestSummaryDelta
          }
        }
        resourcePath
      }
    `,
    pullRequest,
  )

  const filesChangedPath = `${data.resourcePath}/files`
  const filesData: readonly FilesData[] = data.comparison?.summary ?? []

  const additionCount = data.comparison?.linesAdded ?? 0
  const deletionCount = data.comparison?.linesDeleted ?? 0

  return (
    <FilesChangedList
      additionCount={additionCount}
      deletionCount={deletionCount}
      filesChangedPath={filesChangedPath}
      filesData={filesData}
      renderRow={file => <FilesChangedRow key={file.path} file={file} pullRequestPath={data.resourcePath} />}
    />
  )
}
