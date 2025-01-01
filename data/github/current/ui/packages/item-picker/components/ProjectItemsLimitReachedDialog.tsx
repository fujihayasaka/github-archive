import {Dialog} from '@primer/react/experimental'
import {LABELS} from '../constants/labels'

type ProjectItemsLimitReachedDialogProps = {
  onClose: () => void
  returnFocusRef: React.RefObject<HTMLElement>
}

export const ProjectItemsLimitReachedDialog = ({onClose, returnFocusRef}: ProjectItemsLimitReachedDialogProps) => {
  return (
    <Dialog
      aria-label={LABELS.projectItemsLimitReachedDialogLabel}
      title={LABELS.projectItemsLimitReachedDialogTitle}
      onClose={onClose}
      returnFocusRef={returnFocusRef}
      width="large"
      footerButtons={[{content: LABELS.closeButton, onClick: onClose, buttonType: 'primary'}]}
    >
      <div>{LABELS.projectItemsLimitReachedDialogMessage}</div>
    </Dialog>
  )
}
