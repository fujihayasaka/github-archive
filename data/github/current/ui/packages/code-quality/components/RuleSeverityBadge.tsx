import {AlertIcon, CircleSlashIcon, NoteIcon} from '@primer/octicons-react'
import {RuleSeverity} from '../types/rule-severity'
import {Label} from '@primer/react'

export type RuleSeverityBadgeProps = {
  severity: RuleSeverity
}

export function RuleSeverityBadge({severity}: RuleSeverityBadgeProps) {
  switch (severity) {
    case RuleSeverity.Note:
      return (
        <Label variant="secondary">
          <NoteIcon className="color-fg-default pr-1" />
          Note
        </Label>
      )
    case RuleSeverity.Warning:
      return (
        <Label variant="secondary">
          <AlertIcon className="color-fg-attention pr-1" />
          Warning
        </Label>
      )
    case RuleSeverity.Error:
      return (
        <Label variant="secondary">
          <CircleSlashIcon className="color-fg-danger pr-1" />
          Error
        </Label>
      )
  }
}
