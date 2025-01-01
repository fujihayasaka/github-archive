import type {
  FileReference,
  LineRange,
  ReferenceDetails,
  ReferenceHeaderInfo,
  SnippetReference,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {blamePath, commitPath, repoOverviewUrl} from '@github-ui/paths'
import {unqualifyRef} from '@github-ui/ref-utils'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useContributors} from '@github-ui/use-contributors'
import {useLatestCommit} from '@github-ui/use-latest-commit'
import {DownloadIcon, HistoryIcon, LinkExternalIcon, PeopleIcon, RepoIcon} from '@primer/octicons-react'
import {Box, IconButton, LinkButton, RelativeTime, Text, Truncate} from '@primer/react'
import {useCallback, useEffect, useState, type PropsWithChildren} from 'react'

import {ReferencePreview} from './ReferencePreview'
import {SimpleCodeListing} from './SimpleCodeListing'

export function CodeReferencePreview<T extends SnippetReference | FileReference>({
  reference,
  details,
  detailsLoading,
  detailsError,
  onDismiss,
}: {
  reference: T
  details: ReferenceDetails<T> | undefined
  detailsLoading: boolean
  detailsError: boolean
  onDismiss?: () => void
}) {
  const {contributors} = useContributors(reference.repoOwner, reference.repoName, reference.commitOID, reference.path)
  const [latestCommit] = useLatestCommit(reference.repoOwner, reference.repoName, reference.commitOID, reference.path)
  const {lines, lineNumbers, expandUp, expandDown} = useExpandableRange(
    details?.range,
    details?.expandedRange,
    details?.highlightedContents,
  )
  const headerInfo = details?.headerInfo

  return (
    <ReferencePreview.Frame>
      <ReferencePreview.Header onDismiss={onDismiss}>
        <GitHubAvatar square={details?.repoIsOrgOwned} src={`${reference.repoOwner}.png`} sx={{mr: 2, flexShrink: 0}} />
        <Text sx={{fontWeight: 600, whiteSpace: 'nowrap'}}>
          {reference.repoOwner}/{reference.repoName}
        </Text>
        <Text sx={{marginX: 1}}>·</Text>
        <Text sx={{fontWeight: 400}}>{unqualifyRef(reference.ref)}</Text>
        <Text sx={{marginX: 1}}>·</Text>
        <Text
          sx={{fontWeight: 400, textOverflow: 'ellipsis', overflow: 'hidden', whiteSpace: 'nowrap', direction: 'rtl'}}
        >
          {reference.path}
        </Text>
        {reference.type === 'snippet' && (
          <span>
            :{reference.range.start}-{reference.range.end}
          </span>
        )}
      </ReferencePreview.Header>
      <ReferencePreview.Body detailsError={detailsError} detailsLoading={detailsLoading}>
        <Box
          sx={{
            border: '1px solid var(--borderColor-default, var(--color-border-default))',
            borderRadius: '6px 6px 0 0',
            marginX: 3,
          }}
        >
          <BlobPreviewHeader>
            {headerInfo && <BlobSize headerInfo={headerInfo} />}
            {headerInfo && <RawButtons headerInfo={headerInfo} />}
          </BlobPreviewHeader>
          {expandUp && <ReferencePreview.ContentExpander direction="above" onExpand={expandUp} />}
          <ReferencePreview.Content>
            <SimpleCodeListing lines={lines} lineNumbers={lineNumbers} />
          </ReferencePreview.Content>
          {expandDown && <ReferencePreview.ContentExpander direction="below" onExpand={expandDown} />}
        </Box>
        <ReferencePreview.Details>
          <ReferencePreview.DetailLink
            href={repoOverviewUrl({name: reference.repoName, ownerLogin: reference.repoOwner})}
            icon={RepoIcon}
          >
            {reference.repoOwner}/{reference.repoName}
          </ReferencePreview.DetailLink>

          {contributors && (
            <ReferencePreview.DetailLink
              icon={PeopleIcon}
              href={blamePath({
                owner: reference.repoOwner,
                repo: reference.repoName,
                commitish: reference.commitOID,
                filePath: reference.path,
                lineNumber: details?.range.start,
              })}
            >
              {contributors.totalCount} {contributors.totalCount === 1 ? 'contributor' : 'contributors'}
            </ReferencePreview.DetailLink>
          )}

          {latestCommit && (
            <ReferencePreview.DetailLink
              icon={HistoryIcon}
              href={commitPath({owner: reference.repoOwner, repo: reference.repoName, commitish: latestCommit?.oid})}
            >
              {latestCommit?.author?.displayName} updated <RelativeTime datetime={latestCommit?.date} />
            </ReferencePreview.DetailLink>
          )}

          <ReferencePreview.DetailLink icon={LinkExternalIcon} href={reference.url}>
            {reference.repoOwner}/{reference.repoName}/{reference.path}
            {reference.type === 'snippet' ? (
              <>
                #{reference.range.start}-{reference.range.end}
              </>
            ) : null}
          </ReferencePreview.DetailLink>
        </ReferencePreview.Details>
      </ReferencePreview.Body>
    </ReferencePreview.Frame>
  )
}

export function BlobPreviewHeader({children}: PropsWithChildren<object>) {
  return (
    <Box
      sx={{
        p: 2,
        display: 'flex',
        flex: 1,
        alignItems: 'center',
        justifyContent: 'space-between',
        backgroundColor: 'canvas.subtle',
        borderBottom: '1px solid var(--borderColor-default, var(--color-border-default))',
        borderRadius: '6px 6px 0px 0px',
      }}
    >
      {children}
    </Box>
  )
}

export function BlobSize({headerInfo}: {headerInfo: ReferenceHeaderInfo}) {
  return (
    <Truncate title={headerInfo.blobSize} inline sx={{maxWidth: '100%', color: 'fg.subtle'}} data-testid="blob-size">
      <span>{`${headerInfo.lineInfo.truncatedLoc} lines (${headerInfo.lineInfo.truncatedSloc} loc) · ${headerInfo.blobSize}`}</span>
    </Truncate>
  )
}

export function RawButtons({headerInfo}: {headerInfo: ReferenceHeaderInfo}) {
  const lfsDownloadUrl = new URL(headerInfo.rawBlobUrl, ssrSafeLocation.origin)
  lfsDownloadUrl.searchParams.set('download', '')
  const downloadButtonProps = {
    ['aria-label']: 'Download raw content',
    icon: DownloadIcon,
    size: 'small',
    onClick: async () => {
      if (!headerInfo.isLfs) {
        await downloadFile(headerInfo.rawBlobUrl, headerInfo.displayName)
      }
    },
    ['data-testid']: 'download-raw-button',
    sx: {borderTopLeftRadius: 0, borderBottomLeftRadius: 0},
  } as const

  return (
    <Box sx={{display: 'flex'}}>
      <LinkButton
        href={headerInfo.rawBlobUrl}
        download={!headerInfo.viewable ? 'true' : undefined}
        size="small"
        sx={{linkButtonSx, px: 2, borderTopRightRadius: 0, borderBottomRightRadius: 0, borderRight: 'none'}}
        data-testid="raw-button"
      >
        Raw
      </LinkButton>
      {headerInfo.isLfs ? (
        // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
        <IconButton
          unsafeDisableTooltip
          as="a"
          data-turbo="false"
          href={lfsDownloadUrl.toString()}
          {...downloadButtonProps}
        />
      ) : (
        // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
        <IconButton unsafeDisableTooltip {...downloadButtonProps} />
      )}
    </Box>
  )
}

function useExpandableRange<T>(
  range: LineRange | undefined,
  expandedRange: LineRange | undefined,
  allLines: T[] | undefined,
) {
  const [startLine, setStartLine] = useState(range?.start ?? -1)
  const [endLine, setEndLine] = useState(range?.end ?? -1)

  const [lines, setLines] = useState<T[]>(
    allLines && range && expandedRange
      ? allLines.slice(range.start - expandedRange.start, range.end - expandedRange.start + 1)
      : [],
  )

  const updateLines = useCallback(
    (start = startLine, end = endLine) => {
      if (!allLines || !range || !expandedRange || start < 0 || end < 0) return

      setLines(allLines.slice(start - expandedRange.start, end - expandedRange.start + 1))
    },
    [startLine, endLine, allLines, range, expandedRange],
  )

  useEffect(() => {
    if (range && allLines && (startLine === -1 || endLine === -1)) {
      const start = range.start
      const end = range.end
      setStartLine(start)
      setEndLine(end)
      updateLines(start, end)
    }
  }, [allLines, range, expandedRange, updateLines, startLine, endLine])

  const expandUp = useCallback(() => {
    const start = Math.max(startLine - pageSize, expandedRange?.start ?? -1)
    setStartLine(start)
    updateLines(start)
  }, [expandedRange?.start, startLine, updateLines])

  const expandDown = useCallback(() => {
    const end = Math.min(endLine + pageSize, expandedRange?.end ?? -1)
    setEndLine(end)
    updateLines(startLine, end)
  }, [endLine, expandedRange?.end, startLine, updateLines])

  const canExpandUp = startLine !== -1 && startLine !== expandedRange?.start
  const canExpandDown = endLine !== -1 && endLine !== expandedRange?.end

  return {
    lines,
    lineNumbers: lines.map((_, i) => startLine + i),
    expandUp: canExpandUp ? expandUp : null,
    expandDown: canExpandDown ? expandDown : null,
  }
}

const pageSize = 25
const linkButtonSx = {
  '&:hover:not([disabled])': {
    textDecoration: 'none',
  },
  '&:focus:not([disabled])': {
    textDecoration: 'none',
  },
  '&:active:not([disabled])': {
    textDecoration: 'none',
  },
}

async function downloadFile(rawHref: string, name: string) {
  const result = await fetch(rawHref, {method: 'get'})
  const blob = await result.blob()
  const aElement = document.createElement('a')
  aElement.setAttribute('download', name)
  const href = URL.createObjectURL(blob)
  aElement.href = href
  aElement.setAttribute('target', '_blank')
  aElement.click()
  URL.revokeObjectURL(href)
}
