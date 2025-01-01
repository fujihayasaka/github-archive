import {useCallback, useMemo, type ReactNode} from 'react'
import {Dialog, type DialogButtonProps} from '@primer/react/experimental'
import {SyncIcon} from '@primer/octicons-react'
import {useSecurityCampaignFormContext} from './SecurityCampaignFormContext'

export interface SecurityCampaignFormDialogInnerProps {
  setIsOpen: (isOpen: boolean) => void

  dialogTitle: ReactNode
  submitButtonText: ReactNode
  cancelButtonText: ReactNode

  children: ReactNode
}

export function SecurityCampaignFormDialogInner({
  setIsOpen,
  dialogTitle,
  submitButtonText,
  cancelButtonText,
  children,
}: SecurityCampaignFormDialogInnerProps) {
  const {validationError, handleSubmit: handleFormSubmit, resetForm, isPending} = useSecurityCampaignFormContext()

  const onDialogClose = useCallback(() => {
    setIsOpen(false)

    resetForm()
  }, [setIsOpen, resetForm])

  const handleSubmit = useCallback(
    async (e: React.FormEvent<HTMLElement>) => {
      e.preventDefault()

      handleFormSubmit()
    },
    [handleFormSubmit],
  )

  const footerButtons = useMemo<DialogButtonProps[]>(
    () => [
      {
        buttonType: 'default',
        content: cancelButtonText,
        onClick: () => setIsOpen(false),
      },
      {
        buttonType: 'primary',
        content: submitButtonText,
        disabled: !!validationError || isPending,
        onClick: handleSubmit,
        leadingVisual: isPending ? SyncIcon : null,
      },
    ],
    [handleSubmit, isPending, setIsOpen, cancelButtonText, submitButtonText, validationError],
  )

  return (
    <Dialog title={dialogTitle} onClose={onDialogClose} footerButtons={footerButtons}>
      {children}
    </Dialog>
  )
}
