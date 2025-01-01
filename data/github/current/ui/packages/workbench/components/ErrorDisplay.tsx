import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {WorkspaceEditorRoutePayload} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import {Link} from '@primer/react'

import {useEditorContext} from '../contexts/EditorContext'
import {useWorkbenchUI} from '../contexts/WorkbenchUIContext'
import {getErrorSourceLabel, type SparkError} from '../utilities/error'
import styles from './ErrorDisplay.module.css'

interface ErrorDisplayProps {
  error: SparkError
  linkCallback?: () => void
  showSource?: boolean
  truncate?: boolean
}

export function ErrorDisplay({error, linkCallback, showSource, truncate}: ErrorDisplayProps) {
  const {navigateAndViewFile} = useWorkbenchUI()
  const {forceEditorRefresh} = useEditorContext()
  const {path} = useRoutePayload<WorkspaceEditorRoutePayload>()

  if (error.path)
    return (
      <>
        <p className={`mb-0 ${styles.codeText} ${styles.errorContainer}`}>
          {showSource ? <>{getErrorSourceLabel(error.source)} at</> : <>At</>}
          <>&nbsp;</>
          {error.path && (
            <>
              {!error.path?.includes('node_modules') ? (
                <Link
                  inline
                  as="button"
                  className={styles.errorLink}
                  onClick={event => {
                    event.stopPropagation()
                    if (path !== error.path) forceEditorRefresh()
                    navigateAndViewFile(error.path!)
                    linkCallback?.()
                  }}
                >
                  {error.path}
                </Link>
              ) : (
                <span className={styles.errorPath}>{error.path}</span>
              )}
              {error.location && <>{error.location} </>}
            </>
          )}
        </p>
        <p className={`mb-0 ${styles.codeText} ${styles.errorMessage} ${truncate ? styles.truncate1 : ''}`}>
          {error.messagePretty}
        </p>
      </>
    )

  return (
    <p className={`mb-0 ${styles.codeText} ${styles.errorMessage} ${truncate ? styles.truncate2 : ''}`}>
      {showSource && <>{getErrorSourceLabel(error.source)}: </>}
      {error.messagePretty}
    </p>
  )
}
