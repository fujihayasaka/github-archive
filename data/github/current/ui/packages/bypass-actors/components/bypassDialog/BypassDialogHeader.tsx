import {Fragment, useEffect, useRef} from 'react'
import {FormControl, IconButton, TextInput} from '@primer/react'
import {SearchIcon, XIcon} from '@primer/octicons-react'
import {Dialog} from '@primer/react/experimental'
import {type FlashAlert, DismissibleFlashOrToast} from '@github-ui/dismissible-flash'

import styles from './BypassDialogHeader.module.css'
import {clsx} from 'clsx'

const inputPlaceholder = `Search`

type BypassDialogHeaderProps = {
  title?: string
  onClose: () => void
  bypassListFilter: string
  setBypassListFilter: (bypassListFilter: string) => void
  dialogLabelId: string
  flashAlert: FlashAlert
  setFlashAlert: (flashAlert: FlashAlert) => void
  addReviewerSubtitle: string
}

export function BypassDialogHeader({
  title = 'Add bypass',
  onClose,
  bypassListFilter,
  setBypassListFilter,
  dialogLabelId,
  flashAlert,
  setFlashAlert,
  addReviewerSubtitle,
}: BypassDialogHeaderProps) {
  const flashRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    flashRef.current?.focus()
  }, [flashAlert, flashRef])

  return (
    <Fragment>
      <div className={styles.Box}>
        <DismissibleFlashOrToast flashAlert={flashAlert} setFlashAlert={setFlashAlert} ref={flashRef} />
        <div className={styles.Box_1}>
          <Dialog.Title id={dialogLabelId} className={styles.Dialog_Title}>
            {title}
          </Dialog.Title>
          <IconButton variant="invisible" aria-label="Close Dialog" icon={XIcon} onClick={onClose} />
        </div>
        <span className={styles.Text}>{addReviewerSubtitle}</span>
        <FormControl className={styles.FormControl}>
          <FormControl.Label visuallyHidden>Search for bypass actors</FormControl.Label>
          <TextInput
            block={false}
            leadingVisual={SearchIcon}
            placeholder={inputPlaceholder}
            onChange={e => setBypassListFilter(e.target.value)}
            value={bypassListFilter}
            className={styles.TextInput}
          />
        </FormControl>
      </div>
      <div className={clsx('color-bg-subtle color-border-default', styles.Box_2)}>
        <span id="suggestionsHeading" className={clsx('text-small', styles.Text_1)}>
          Suggestions
        </span>
      </div>
    </Fragment>
  )
}
