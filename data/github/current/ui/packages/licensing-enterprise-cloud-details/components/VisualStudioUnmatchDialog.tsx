import {Dialog, Stack} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {clsx} from 'clsx'
import styles from './VisualStudioUnmatchDialog.module.css'

export interface VisualStudioUnmatchDialogProps {
  errorMessage: string | null
  isSaving: boolean
  isVolumeLicensed: boolean
  onClose: () => void
  onConfirm: () => void
  onDismissError: () => void
}

export function VisualStudioUnmatchDialog(props: VisualStudioUnmatchDialogProps) {
  return (
    <Dialog
      title="Change to GitHub Enterprise license"
      subtitle={`You're about to convert this user's current Visual Studio subscription to a ${
        props.isVolumeLicensed ? '' : ' metered'
      } GitHub Enterprise license.`}
      width="large"
      onClose={props.onClose}
      footerButtons={[
        {buttonType: 'default', content: 'Cancel', onClick: props.onClose},
        {
          buttonType: 'primary',
          content: 'Confirm change',
          onClick: props.onConfirm,
          disabled: props.isSaving,
        },
      ]}
    >
      <Stack direction="vertical">
        {props.errorMessage && (
          <Banner variant="critical" title="Error saving license change" hideTitle onDismiss={props.onDismissError}>
            {props.errorMessage}
          </Banner>
        )}
        <Stack direction="horizontal" gap="normal">
          <Stack direction="vertical" gap="none" className={clsx(styles.vsDialogCol)}>
            <div className="f6 fgColor-muted text-semibold">Current:</div>
            <div className="f5 text-semibold">Visual Studio subscription</div>
            <div className="f6 fgColor-muted">Managed by your Visual Studio agreement</div>
          </Stack>
          <Stack direction="vertical" gap="none" className={clsx(styles.vsDialogCol)}>
            <div className="f6 fgColor-muted text-semibold">New:</div>
            <div className="f5 text-semibold">GitHub Enterprise</div>
            {!props.isVolumeLicensed && <div className="f6 fgColor-muted">Billed at $21/user per month</div>}
          </Stack>
        </Stack>
        <div className="f5 fgColor-muted">The license will be applied and billed immediately.</div>
      </Stack>
    </Dialog>
  )
}
