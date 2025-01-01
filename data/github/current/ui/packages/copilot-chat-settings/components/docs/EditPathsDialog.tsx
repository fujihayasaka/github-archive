import type {DocsetRepo} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {FormControl, Link, Textarea} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {useCallback, useRef} from 'react'

import styles from './EditPathsDialog.module.css'

export function EditPathsDialog({onClose, repo}: {onClose: () => void; repo: DocsetRepo}) {
  const onCancel = onClose
  const onOk = useCallback(() => {
    const pathText = pathsRef.current?.value ?? ''
    const paths = pathText
      .split('\n')
      .map(path => path.trim())
      .filter(path => path !== '')
    // eslint-disable-next-line react-hooks/react-compiler
    repo.paths = paths
    onClose()
  }, [onClose, repo])
  const pathsRef = useRef<HTMLTextAreaElement>(null)

  return (
    <Dialog
      footerButtons={[
        {buttonType: 'normal', content: 'Cancel', onClick: onCancel},
        {buttonType: 'primary', content: 'Apply', onClick: onOk},
      ]}
      renderFooter={({footerButtons}) => {
        return (
          <Dialog.Footer className={styles.Dialog_Footer}>
            {footerButtons && <Dialog.Buttons buttons={footerButtons} />}
          </Dialog.Footer>
        )
      }}
      onClose={onCancel}
      subtitle={`Define which paths within ${repo.nameWithOwner} that should be included within this docset.`}
      title="Edit paths"
      className={styles.Dialog}
    >
      <span>
        Use globs accepted by the{' '}
        <Link
          href="https://docs.github.com/en/search-github/github-code-search/understanding-github-code-search-syntax#path-qualifier"
          inline
          target="_blank"
        >
          code search path qualifier
        </Link>
        , one per line. Only files ending in .md and .mdx are indexed.
      </span>
      <FormControl className={styles.FormControl}>
        <FormControl.Label>Paths</FormControl.Label>
        <Textarea
          ref={pathsRef}
          placeholder="e.g. /docs/**/*"
          defaultValue={repo.paths.join('\n')}
          className={styles.Textarea}
        />
      </FormControl>
      <span className={styles.Text}>If no paths are provided, all md and mdx files will be searched.</span>
    </Dialog>
  )
}
