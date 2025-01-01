import {Dialog, type DialogHeaderProps, type DialogProps} from '@primer/react'
import {type PropsWithChildren, type RefObject, useRef} from 'react'

type PrimerDialogProps = Pick<DialogProps, 'onClose' | 'returnFocusRef' | 'footerButtons' | 'renderBody'>

interface Props extends PrimerDialogProps {
  renderHeader: React.FunctionComponent<
    React.PropsWithChildren<DialogHeaderProps & {initialFocusRef: RefObject<HTMLInputElement>}>
  >
}

export function PickerDialog({renderHeader, ...props}: Props) {
  const initialFocusRef = useRef<HTMLInputElement>(null)

  return (
    <Dialog
      {...props}
      height="small"
      initialFocusRef={initialFocusRef}
      renderHeader={headerProps => renderHeader({...headerProps, initialFocusRef})}
    />
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
