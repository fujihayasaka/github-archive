import {ScopedCommands} from '@github-ui/ui-commands'
import {Dialog, type DialogHeaderProps, type DialogProps} from '@primer/react'
import {type PropsWithChildren, type RefObject, useRef} from 'react'

import styles from './PickerDialog.module.css'

type PrimerDialogProps = Pick<DialogProps, 'onClose' | 'returnFocusRef' | 'footerButtons' | 'renderBody'>

interface Props extends PrimerDialogProps {
  renderHeader: React.FunctionComponent<
    React.PropsWithChildren<DialogHeaderProps & {initialFocusRef: RefObject<HTMLInputElement>}>
  >
  onRenderFooterDetails?: () => React.ReactNode
  onSubmit?: () => void
}

export function PickerDialog({footerButtons, renderHeader, onRenderFooterDetails, onSubmit, ...props}: Props) {
  const initialFocusRef = useRef<HTMLInputElement>(null)

  const footerProps = onRenderFooterDetails
    ? {
        renderFooter: () => (
          <Dialog.Footer>
            {onRenderFooterDetails()}
            {footerButtons && <Dialog.Buttons buttons={footerButtons} />}
          </Dialog.Footer>
        ),
      }
    : {
        footerButtons,
      }

  return (
    <ScopedCommands commands={{'github:submit-form': onSubmit}}>
      <Dialog
        {...props}
        className={styles.Dialog}
        position={{narrow: 'bottom', regular: 'center'}}
        height="small"
        initialFocusRef={initialFocusRef}
        renderHeader={headerProps => renderHeader({...headerProps, initialFocusRef})}
        {...footerProps}
      />
    </ScopedCommands>
  )
}

PickerDialog.Body = ReposPickerBody

function ReposPickerBody({children}: PropsWithChildren) {
  return (
    <Dialog.Body className="p-0" data-testid="repos-picker-dialog-body">
      {children}
    </Dialog.Body>
  )
}
