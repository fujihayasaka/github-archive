import {ActionList, Link} from '@primer/react'
import {FileStatusIcon} from '@github-ui/diff-file-tree/file-status-icon'
import {FileSubmoduleIcon} from '@primer/octicons-react'
import {LinesChangedCounterLabel} from '@github-ui/diff-file-header'
import type {SubmoduleDiff as SubmoduleDiffType, SummaryDelta} from '../types'
import {useMemo} from 'react'

export type SubmoduleDiffProps = {
  submodule: SubmoduleDiffType
}

export function SubmoduleDiff({submodule}: SubmoduleDiffProps) {
  const {basePath, changedFiles, contentsUrl, newCommitOid, oldCommitOid, status, submoduleUrl} = submodule
  const renderSummaries = submodule.summary.length > 0 && submodule.contentsUrl && status === 'MODIFIED'

  const submoduleChange = useMemo(() => {
    switch (status) {
      case 'ADDED':
        return <SubmoduleCommitChange commitOid={newCommitOid} contentsUrl={contentsUrl} type="added" />
      case 'DELETED':
      case 'REMOVED':
        return <SubmoduleCommitChange commitOid={oldCommitOid} contentsUrl={contentsUrl} type="deleted" />
      case 'MODIFIED':
      default:
        return (
          <SubmoduleModified
            newCommitOid={newCommitOid}
            oldCommitOid={oldCommitOid}
            changedFiles={changedFiles}
            contentsUrl={contentsUrl}
          />
        )
    }
  }, [newCommitOid, oldCommitOid, status, changedFiles, contentsUrl])

  return (
    <div>
      <div className={`px-3 py-2 ${renderSummaries ? 'border-bottom bgColor-muted' : ''}`}>
        <FileSubmoduleIcon className="fgColor-muted mr-2" size={16} />
        <SubmodulePath basePath={basePath} submoduleUrl={submoduleUrl} />
        {submoduleChange}
      </div>

      {renderSummaries && (
        <ActionList className="pt-0" showDividers variant="full" sx={{'> li': {borderRadius: 0}}}>
          {submodule.summary.map(summary => (
            <SubmoduleFileRow
              key={summary.pathDigest}
              compareUrl={`${contentsUrl}/compare/${oldCommitOid}...${newCommitOid}`}
              linesAdded={summary.linesAdded}
              linesDeleted={summary.linesDeleted}
              path={summary.path}
              pathDigest={summary.pathDigest}
              status={summary.status}
            />
          ))}
        </ActionList>
      )}
    </div>
  )
}

function SubmodulePath({basePath, submoduleUrl}: {basePath: string; submoduleUrl?: string}) {
  return (
    <>
      Submodule{' '}
      {submoduleUrl ? (
        <Link inline href={submoduleUrl}>
          {basePath}
        </Link>
      ) : (
        basePath
      )}{' '}
    </>
  )
}

function shortSha(sha: string) {
  return sha.slice(0, 7)
}

function SubmoduleCommitChange({
  commitOid = '',
  contentsUrl,
  type,
}: {
  commitOid?: string
  contentsUrl?: string
  type: 'added' | 'deleted'
}) {
  const text = type === 'added' ? 'added at' : 'deleted from'

  if (contentsUrl) {
    return (
      <>
        {text}{' '}
        <Link inline href={`${contentsUrl}/tree/${commitOid}`}>
          {shortSha(commitOid)}
        </Link>
      </>
    )
  } else {
    return (
      <>
        {text} {shortSha(commitOid)}
      </>
    )
  }
}

function SubmoduleModified({
  newCommitOid = '',
  oldCommitOid = '', // 0 out
  changedFiles = 0,
  contentsUrl,
}: {
  newCommitOid?: string
  oldCommitOid?: string
  changedFiles?: number
  contentsUrl?: string
}) {
  const compareText =
    changedFiles > 0 && contentsUrl
      ? `${changedFiles} ${changedFiles === 1 ? 'file' : 'files'}`
      : `from ${shortSha(oldCommitOid)} to ${shortSha(newCommitOid)}`

  return (
    <>
      updated{' '}
      {contentsUrl ? (
        <Link inline href={`${contentsUrl}/compare/${oldCommitOid}...${newCommitOid}`}>
          {compareText}
        </Link>
      ) : (
        compareText
      )}
    </>
  )
}

function SubmoduleFileRow({
  compareUrl,
  linesAdded,
  linesDeleted,
  path,
  pathDigest,
  status,
}: SummaryDelta & {compareUrl: string}) {
  return (
    <ActionList.LinkItem
      href={`${compareUrl}#diff-${pathDigest}`}
      sx={{
        px: 0,
        borderRadius: 0,
        '&:hover .path, &:focus .path': {
          color: 'accent.fg',
          textDecoration: 'underline',
        },
      }}
    >
      <div className="d-flex gap-2 flex-row flex-items-center pl-3" style={{maxWidth: '500px'}}>
        <FileStatusIcon status={status} />
        <div className="d-flex gap-1 flex-justify-between width-full">
          <span className="path">{path}</span>
          {(linesAdded > 0 || linesDeleted > 0) && (
            <div className="d-flex flex-shrink-0 gap-1 flex-nowrap">
              <div style={{minWidth: '5ch', textAlign: 'right'}}>
                {linesAdded > 0 && (
                  <LinesChangedCounterLabel isAddition>+{formatCount(linesAdded)}</LinesChangedCounterLabel>
                )}
              </div>
              <div style={{width: '5ch', textAlign: 'left'}}>
                {linesDeleted > 0 && (
                  <LinesChangedCounterLabel isAddition={false}>-{formatCount(linesDeleted)}</LinesChangedCounterLabel>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </ActionList.LinkItem>
  )
}

function formatCount(count: number): string {
  if (count > 999) {
    // Truncate display to something like "4.2k"
    return `${(count / 1000).toFixed(1)}k`
  }

  return count.toLocaleString()
}
