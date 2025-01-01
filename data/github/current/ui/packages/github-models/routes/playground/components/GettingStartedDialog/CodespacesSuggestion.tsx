import {Button} from '@primer/react'
import {CodespacesIcon} from '@primer/octicons-react'
import {RunCodespaceButtonClicked} from '../../../../utils/playground-types'
import {sendEvent} from '@github-ui/hydro-analytics'
import styles from './CodespacesSuggestion.module.css'

export default function CodespacesSuggestion({openInCodespaceUrl}: {openInCodespaceUrl: string}) {
  return (
    <div className={styles.codespacesSuggestionContainer}>
      <span className={styles.runCodespacesText}>Run with codespaces</span>
      <span className={styles.runCodespacesSubtitle}>
        Seriously, you&apos;ll be up and running in seconds. It will be great.
      </span>
      <div className={styles.codespacesButtonContainer}>
        <Button
          as="a"
          leadingVisual={CodespacesIcon}
          variant="primary"
          href={openInCodespaceUrl}
          onClick={() => sendEvent(RunCodespaceButtonClicked)}
          target="_blank"
        >
          Run codespace
        </Button>
      </div>
    </div>
  )
}
