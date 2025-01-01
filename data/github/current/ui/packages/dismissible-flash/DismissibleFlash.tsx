import {XIcon} from '@primer/octicons-react'
import {Flash, IconButton} from '@primer/react'
import {forwardRef, type ComponentProps, type ForwardedRef, type PropsWithChildren, type ReactNode} from 'react'

interface DismissibleFlashProps {
  variant: ComponentProps<typeof Flash>['variant']
  onClose(): void
}

function DismissibleFlashWithRef(
  {variant, onClose, children}: PropsWithChildren<DismissibleFlashProps>,
  ref: ForwardedRef<HTMLDivElement>,
): JSX.Element | null {
  return (
    <Flash
      sx={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        pl: 3,
        pr: 2,
        py: 2,
        mb: 3,
      }}
      variant={variant}
      tabIndex={0}
      ref={ref}
    >
      {children}
      <IconButton
        variant="invisible"
        icon={XIcon}
        aria-label="Dismiss message"
        sx={{'>svg': {m: 0, color: 'fg.muted'}}}
        onClick={onClose}
        size="small"
      />
    </Flash>
  )
}

// switch to new Primer React "Banner" component when it's ready: https://github.com/github/primer/issues/2807
export const DismissibleFlash = forwardRef(DismissibleFlashWithRef)

export type FlashAlert = {message: string; icon?: ReactNode; variant: ComponentProps<typeof Flash>['variant']}

function resetFlashAlert(setFlashAlert: (flashAlert: FlashAlert) => void) {
  setFlashAlert({message: '', variant: 'default'})
}

interface DismissibleFlashOrToastProps {
  flashAlert: FlashAlert
  setFlashAlert: (flashAlert: FlashAlert) => void
}

function DismissibleFlashOrToastWithRef(
  {flashAlert, setFlashAlert}: DismissibleFlashOrToastProps,
  ref: ForwardedRef<HTMLDivElement>,
): JSX.Element | null {
  if (flashAlert.message) {
    return (
      <DismissibleFlash variant={flashAlert.variant} onClose={() => resetFlashAlert(setFlashAlert)} ref={ref}>
        {flashAlert.message}
      </DismissibleFlash>
    )
  }
  return null
}

export const DismissibleFlashOrToast = forwardRef(DismissibleFlashOrToastWithRef)
