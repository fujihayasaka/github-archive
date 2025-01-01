import {DiffFileHeader} from '@github-ui/diff-file-header'
import {
  fileCopiedOnly,
  fileModeChangedOnlyNoOtherChanges,
  fileRenamedOnly,
  fileTruncated,
  fileWasDeleted,
  fileWasGenerated,
  truncatedReason,
  whitespaceChangedOnly,
} from '@github-ui/diff-file-helpers'
import {getLineNumberWidth} from '@github-ui/diffs/diff-line-helpers'
import {UnifiedDiffLines} from '@github-ui/diffs/DiffParts'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {PencilIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {type PropsWithChildren, useMemo, useState} from 'react'
import {useLocation, useNavigate} from 'react-router-dom'

import {useCurrentPullRequest} from '../../contexts/CurrentPullRequestProvider'
import type {DiffData} from '../../utilities/diff-analysis'
import {fileUrl} from '../../utilities/urls'
import type {WorkspaceEditorRoutePayload} from '../../utilities/workspace-editor-types'
import styles from '../Diff.module.css'

function PlainTextStatus({children}: PropsWithChildren) {
  return <div className="border-left border-right fgColor-muted p-2">{children}</div>
}

function getHideDiffLinesReason(diff: DiffData) {
  let hideDiffLinesReason: string | undefined
  if (diff.isBinary) {
    hideDiffLinesReason = 'Binary file not shown.'
  } else if (fileRenamedOnly(diff)) {
    hideDiffLinesReason = 'File renamed without changes.'
  } else if (fileCopiedOnly(diff)) {
    hideDiffLinesReason = 'File copied without changes.'
  } else if (fileModeChangedOnlyNoOtherChanges(diff, diff.status, diff.oldTreeEntry?.mode, diff.newTreeEntry?.mode)) {
    hideDiffLinesReason = 'File mode changed.'
  } else if (fileTruncated(diff)) {
    // Safe, because we just validated that field exists in the predicate above.

    hideDiffLinesReason = truncatedReason(diff.truncatedReason as string)
  } else if (whitespaceChangedOnly(diff)) {
    hideDiffLinesReason = 'Whitespace-only changes.'
  } else if (fileWasDeleted(diff)) {
    hideDiffLinesReason = 'This file was deleted.'
  } else if (fileWasGenerated(diff)) {
    hideDiffLinesReason = 'Some generated files are not rendered by default.'
  } else if (diff.isTooBig) {
    hideDiffLinesReason = 'File is too large to render.'
  }

  return hideDiffLinesReason
}

function DiffContent({diff}: {diff: DiffData}) {
  // Remove the first character from the diff lines, which is an added, removed, or context line indicator
  const diffLines = useMemo(() => {
    return diff.diffLines.map(line => ({
      ...line,
      html: line.html.substring(1),
      text: line.text.substring(1),
    }))
  }, [diff.diffLines])

  const lineWidth = getLineNumberWidth(diffLines)
  const hideDiffLinesReasonString = getHideDiffLinesReason(diff)

  if (hideDiffLinesReasonString) {
    return <PlainTextStatus>{hideDiffLinesReasonString}</PlainTextStatus>
  }

  return <UnifiedDiffLines lines={diffLines} lineWidth={lineWidth} tabSize={2} />
}

export function OverviewDiff({diff}: {diff: DiffData}) {
  const {repo} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()
  const [isCollapsed, setIsCollapsed] = useState(true)
  const location = useLocation()
  const navigate = useNavigate()

  const urlToFile = fileUrl({
    owner: repo.ownerLogin,
    repo: repo.name,
    path: diff.path,
    pullNumber: pullRequest.number,
    location,
  })

  const handleNavigateToFile = () => navigate(urlToFile)

  return (
    <div className={isCollapsed ? undefined : styles.diff}>
      <DiffFileHeader
        className="p-1"
        isCollapsed={isCollapsed}
        linesAdded={diff.linesAdded}
        linesChanged={diff.linesChanged}
        linesDeleted={diff.linesDeleted}
        newMode={diff.newTreeEntry?.mode}
        newPath={diff.newTreeEntry?.path}
        oldMode={diff.oldTreeEntry?.mode}
        oldPath={diff.oldTreeEntry?.path}
        onHeaderClick={handleNavigateToFile}
        onToggleFileCollapsed={() => setIsCollapsed(!isCollapsed)}
        patchStatus={diff.status}
        path={diff.path}
        rightSideContent={
          <IconButton
            as="a"
            aria-label={`Go to ${diff.path}`}
            icon={PencilIcon}
            href={urlToFile}
            onClick={e => {
              e.preventDefault()
              handleNavigateToFile()
            }}
            tooltipDirection="nw"
            variant="invisible"
          />
        }
      />
      {!isCollapsed && <DiffContent diff={diff} />}
    </div>
  )
}
