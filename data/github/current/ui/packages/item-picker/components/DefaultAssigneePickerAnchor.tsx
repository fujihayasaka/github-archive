import {forwardRef} from 'react'
import type {AssigneePickerProps} from './AssigneePicker'
import {CompressedAssigneeAnchor} from './CompressedAssigneeAnchor'

type DefaultAssigneePickerAnchorProps = Pick<AssigneePickerProps, 'assignees' | 'readonly'> & {
  anchorProps?: React.HTMLAttributes<HTMLElement> | undefined
}

export const DefaultAssigneePickerAnchor = forwardRef<HTMLButtonElement, DefaultAssigneePickerAnchorProps>(
  ({assignees, readonly, anchorProps}, ref) => {
    return (
      <CompressedAssigneeAnchor
        assignees={assignees}
        displayHotkey={false}
        anchorProps={readonly ? undefined : anchorProps}
        readonly={readonly}
        ref={ref}
      />
    )
  },
)

DefaultAssigneePickerAnchor.displayName = 'DefaultAssigneePickerAnchor'
