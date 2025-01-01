import {useFilesPageInfo} from '../../contexts/FilesPageInfoContext'
import {useCurrentRepository} from '@github-ui/current-repository'
import {repositoryTreePath} from '@github-ui/paths'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {HourglassIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {SharedMarkdownContent} from '../SharedMarkdownContent'

import styles from './DirectoryRichtextContent.module.css'

export function DirectoryRichtextContent({
  errorMessage,
  onAnchorClick,
  path,
  richText,
  stickyHeaderHeight,
  timedOut,
}: {
  errorMessage?: string
  onAnchorClick?: (event: React.MouseEvent) => void
  path: string
  richText: SafeHTMLString | null
  stickyHeaderHeight?: number
  timedOut?: boolean
}) {
  const repo = useCurrentRepository()
  const {refInfo} = useFilesPageInfo()
  if (errorMessage) {
    return (
      <div className="py-6 px-3 text-center">
        {timedOut && <Octicon icon={HourglassIcon} size={32} />}
        <div data-testid="directory-richtext-error-message">{errorMessage}</div>
        {timedOut && (
          <div>
            But you can view the{' '}
            <Link
              inline
              href={repositoryTreePath({repo, commitish: refInfo.name, action: 'raw', path})}
              data-testid="directory-richtext-timeout-raw-link"
            >
              raw file
            </Link>
            .
          </div>
        )}
      </div>
    )
  } else if (richText) {
    return (
      <SharedMarkdownContent
        onAnchorClick={onAnchorClick}
        richText={richText}
        stickyHeaderHeight={stickyHeaderHeight}
        className={styles.SharedMarkdownContent}
      />
    )
  }
  return null
}
