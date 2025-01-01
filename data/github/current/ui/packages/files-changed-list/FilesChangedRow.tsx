import {LinesChangedCounterLabel} from '@github-ui/diff-file-header'
import type {PatchStatus} from '@github-ui/diff-file-helpers'
import {FileStatusIcon} from '@github-ui/diff-file-tree/file-status-icon'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {useNavigate} from '@github-ui/use-navigate'
import {CommentIcon} from '@primer/octicons-react'
import {Box} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import styles from './FilesChangedRow.module.css'

function pluralize(word: string, count: number) {
  return `${word}${count > 1 ? 's' : ''}`
}

function rtlFix(path: string): string {
  return path.startsWith('.') ? `&lrm;${path}` : path
}

function StyledMetadata({children}: {children: React.ReactNode}) {
  return (
    <Box
      sx={{
        width: '5ch',
        display: ['none', 'flex'],
        alignItems: 'center',
        justifyContent: 'flex-end',
        gap: 1,
      }}
    >
      {children}
    </Box>
  )
}

export interface FilesChangedRowProps {
  filePathUrl: string
  unresolvedCommentCount?: number
  additions: number
  deletions: number
  path: string
  changeType: PatchStatus
}

export function FilesChangedRow({
  filePathUrl,
  unresolvedCommentCount,
  additions,
  deletions,
  path,
  changeType,
}: FilesChangedRowProps) {
  const navigate = useNavigate()
  const unresolvedCommentLabel =
    unresolvedCommentCount && `${unresolvedCommentCount} unresolved ${pluralize('comment', unresolvedCommentCount)}`
  const additionsLabel = additions && `${additions} ${pluralize('addition', additions)}`
  const deletionsLabel = deletions && `${deletions} ${pluralize('deletion', deletions)}`
  const metadataLabel = [unresolvedCommentLabel, additionsLabel, deletionsLabel].filter(label => !!label).join(', ')

  const rowAriaLabel = `${path}: ${metadataLabel}`

  return (
    <ListItem
      aria-label={rowAriaLabel}
      metadata={
        <>
          {unresolvedCommentCount !== undefined && (
            <StyledMetadata>
              {unresolvedCommentCount > 0 && (
                <>
                  <Octicon icon={CommentIcon} size={16} sx={{color: 'fg.muted'}} />
                  <span className="sr-only">
                    {`has ${unresolvedCommentCount} ${pluralize('comment', unresolvedCommentCount)}`}
                  </span>
                  <Box aria-hidden sx={{fontWeight: 600, fontSize: 0}}>
                    {unresolvedCommentCount}
                  </Box>
                </>
              )}
            </StyledMetadata>
          )}
          <StyledMetadata>
            {additions > 0 && (
              <LinesChangedCounterLabel isAddition className={styles.linesChanged}>
                +{additions}
              </LinesChangedCounterLabel>
            )}
          </StyledMetadata>
          <StyledMetadata>
            {deletions > 0 && (
              <LinesChangedCounterLabel isAddition={false} className={styles.linesChanged}>
                -{deletions}
              </LinesChangedCounterLabel>
            )}
          </StyledMetadata>
        </>
      }
      title={
        <ListItemTitle
          href={filePathUrl}
          value={rtlFix(path)}
          onClick={e => {
            e.preventDefault()
            navigate(filePathUrl)
          }}
          anchorClassName={styles.ListItemTitle_0}
        />
      }
    >
      <ListItemLeadingContent>
        <Box sx={{display: 'flex', alignItems: 'center', height: '100%'}}>
          <FileStatusIcon status={changeType} />
        </Box>
      </ListItemLeadingContent>
    </ListItem>
  )
}
