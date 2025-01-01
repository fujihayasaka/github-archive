import {DialogType} from '../utils/copilot-chat-types'
import {ExperimentsDialog} from './ExperimentsDialog'
import {PromptDialog} from './PromptDialog'

export interface StaffDialogProps {
  dialogType: DialogType
  staffDialogRef: React.MutableRefObject<HTMLDivElement | null>
  onDismiss: () => void
}

export const StaffDialogs = ({dialogType, onDismiss, staffDialogRef}: StaffDialogProps): JSX.Element => {
  return (
    <>
      {dialogType === DialogType.Experiments && (
        <ExperimentsDialog experimentsDialogRef={staffDialogRef} onDismiss={onDismiss} />
      )}
      {dialogType === DialogType.Prompt && <PromptDialog promptDialogRef={staffDialogRef} onDismiss={onDismiss} />}
    </>
  )
}
