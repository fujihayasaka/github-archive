import {LinesChangedCounterLabel} from '@github-ui/diff-file-header'
import {ListView} from '@github-ui/list-view'
import {Link} from '@github-ui/react-core/link'
import {useNavigate} from '@github-ui/use-navigate'
import {FileDiffIcon} from '@primer/octicons-react'
import {Box, Button, CounterLabel, Heading} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import styles from './FilesChangedList.module.css'

export interface FilesChangedListProps<T> {
  additionCount: number
  deletionCount: number
  filesChangedPath?: string
  filesData: readonly T[]
  renderRow: (file: T) => JSX.Element
  maxFilesToShow?: number
}

export function FilesChangedList<T>({
  additionCount,
  deletionCount,
  filesChangedPath,
  filesData,
  renderRow,
  maxFilesToShow = 15,
}: FilesChangedListProps<T>) {
  const navigate = useNavigate()

  const currentFilesVisible = Math.min(maxFilesToShow, filesData.length)
  const listIsTruncated = filesData.length > currentFilesVisible

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        gap: 2,
      }}
    >
      <Box
        data-testid="files-changed-heading-container"
        sx={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 2}}
      >
        <Heading as="h2" id="files-changed-heading" sx={{fontSize: 3, display: 'flex', alignItems: 'center', gap: 2}}>
          Files changed
          <CounterLabel>{filesData.length}</CounterLabel>
        </Heading>
        {filesData.length > 1 && (
          <Box sx={{display: 'flex', gap: 2, mr: 3}}>
            <Box sx={{width: '5ch'}}>
              {additionCount > 0 ? (
                <LinesChangedCounterLabel isAddition className={styles.linesChanged}>
                  +{additionCount}
                </LinesChangedCounterLabel>
              ) : null}
            </Box>
            <Box sx={{width: '5ch', mr: 1}}>
              {deletionCount > 0 ? (
                <LinesChangedCounterLabel className={styles.linesChanged}>-{deletionCount}</LinesChangedCounterLabel>
              ) : null}
            </Box>
          </Box>
        )}
      </Box>
      {filesData.length > 0 ? (
        <Box
          sx={{
            border: '1px solid',
            borderColor: 'border.muted',
            borderRadius: 2,
          }}
        >
          <ListView ariaLabelledBy="files-changed-heading" title="Files changed" variant="compact">
            {filesData.slice(0, maxFilesToShow).map(file => {
              return renderRow(file)
            })}
          </ListView>
          {(listIsTruncated || filesChangedPath) && (
            <Box
              sx={{
                backgroundColor: 'canvas.subtle',
                borderTop: '1px solid',
                borderTopColor: 'border.muted',
                borderBottomLeftRadius: 2,
                borderBottomRightRadius: 2,
                pl: 3,
                pr: 1,
                py: 1,
                display: 'flex',
                justifyContent: 'flex-end',
                alignItems: 'center',
              }}
            >
              {listIsTruncated && (
                <Box sx={{fontSize: 0, color: 'fg.muted', flexGrow: 1}}>
                  Showing{' '}
                  <Box as="span" sx={{color: 'fg.default', fontWeight: 500}}>
                    {currentFilesVisible}
                  </Box>{' '}
                  of{' '}
                  <Box as="span" sx={{color: 'fg.default', fontWeight: 500}}>
                    {filesData.length}
                  </Box>{' '}
                  changed files
                </Box>
              )}
              {filesChangedPath && (
                <Button
                  as={Link}
                  to={filesChangedPath}
                  variant="invisible"
                  onClick={e => {
                    e.preventDefault()
                    navigate(filesChangedPath)
                  }}
                >
                  View {listIsTruncated ? 'all ' : ''}files changed
                </Button>
              )}
            </Box>
          )}
        </Box>
      ) : (
        <Blankslate border>
          <Blankslate.Visual>
            <Box sx={{color: 'fg.muted'}}>
              <FileDiffIcon size="medium" />
            </Box>
          </Blankslate.Visual>
          <Blankslate.Heading>There are no changes to display</Blankslate.Heading>
          <Blankslate.Description>
            This branch does not contain any changes compared to the base branch.
          </Blankslate.Description>
        </Blankslate>
      )}
    </Box>
  )
}
