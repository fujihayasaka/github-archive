import {GitHubAvatar} from '@github-ui/github-avatar'
import {userHovercardPath} from '@github-ui/paths'
import {CopilotIcon, PeopleIcon} from '@primer/octicons-react'
import {forwardRef} from 'react'
import {HOTKEYS} from '../constants/hotkeys'
import {LABELS} from '../constants/labels'
import type {Assignee} from './AssigneePicker'
import {SharedPicker} from './SharedPicker'

// At this point, we don't require that the Assignee type needs to come from Relay, so we remove the Relay
// internal fragment type property and other unused properties, so it's easier to re-use this component in other contexts.
// For example, when populating assignees within a project grouped by assignees.
export type AssigneeObject = Pick<Assignee, 'login' | 'avatarUrl' | 'isCopilot'>

export type CompressedAssigneeAnchorProps = {
  assignees: AssigneeObject[]
  anchorProps?: React.HTMLAttributes<HTMLElement>
  displayHotkey: boolean
  MAX_DISPLAYED_ASSIGNEES?: number
  readonly?: boolean
}

export const CompressedAssigneeAnchor = forwardRef<HTMLButtonElement, CompressedAssigneeAnchorProps>(
  ({assignees, anchorProps, displayHotkey, MAX_DISPLAYED_ASSIGNEES = 2, readonly}, ref) => {
    return (
      <SharedPicker
        leadingIconElement={assignees.slice(0, MAX_DISPLAYED_ASSIGNEES).map(a => (
          <AssigneeLeadingVisual assignee={a} key={a.login} />
        ))}
        anchorText={assignees.length > 1 ? LABELS.assignees : LABELS.noAssignees}
        anchorProps={anchorProps}
        sharedPickerMainValue={assignees
          .slice(0, MAX_DISPLAYED_ASSIGNEES)
          .map(a => (a.isCopilot ? 'Copilot' : a.login))
          .join(', ')
          .concat(assignees.length > MAX_DISPLAYED_ASSIGNEES ? `, ${assignees.length - MAX_DISPLAYED_ASSIGNEES}+` : '')}
        ariaLabel={LABELS.selectAssignees}
        readonly={readonly}
        leadingIcon={PeopleIcon}
        hotKey={!readonly && displayHotkey ? HOTKEYS.assigneePicker.toUpperCase() : undefined}
        ref={ref}
      />
    )
  },
)

function AssigneeLeadingVisual({assignee}: {assignee: AssigneeObject}) {
  if (assignee.isCopilot) {
    return <CopilotIcon />
  } else {
    return (
      <GitHubAvatar
        data-hovercard-url={userHovercardPath({owner: assignee.login})}
        src={assignee.avatarUrl}
        size={16}
        alt={`@${assignee.login}`}
        sx={{boxShadow: '0 0 0 2px var(--bgColor-muted, var(--color-canvas-subtle))'}}
      />
    )
  }
}

CompressedAssigneeAnchor.displayName = 'CompressedAssigneeAnchor'
