import {MarkdownIcon} from '@primer/octicons-react'
import {Tooltip} from '@primer/react/next'

import styles from './MarkdownIndicator.module.css'

type MarkdownIndicatorProps = {
  markdownDocsUrl: string
}

export function MarkdownIndicator({markdownDocsUrl}: MarkdownIndicatorProps) {
  return (
    <div className={styles.container}>
      <Tooltip text="Styling with Markdown is supported" direction="nw">
        <a
          className="Link--muted d-inline"
          href={markdownDocsUrl}
          target="_blank"
          data-ga-click="Markdown Toolbar, click, help"
          aria-label="View Markdown documentation"
          rel="noreferrer"
        >
          <MarkdownIcon size={16} />
        </a>
      </Tooltip>
    </div>
  )
}
