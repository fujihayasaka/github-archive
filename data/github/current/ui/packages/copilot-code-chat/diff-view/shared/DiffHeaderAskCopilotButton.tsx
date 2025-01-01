import {CopilotIcon, TriangleDownIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {Tooltip} from '@primer/react/deprecated'
import {memo} from 'react'
import styles from './DiffHeaderAskCopilotButton.module.css'
import type {ButtonProps} from '@primer/react'
import {copilotDiffHeaderButtonID, copilotChatPanelID} from '@github-ui/copilot-chat/utils/constants'

const askCopilotButtonProps = {
  id: copilotDiffHeaderButtonID,
  size: 'small',
  leadingVisual: CopilotIcon,
  className: styles.askCopilotButton,
  children: 'Ask Copilot',
  trailingVisual: TriangleDownIcon,
  'aria-controls': copilotChatPanelID,
  'aria-expanded': false,
} as const satisfies Partial<ButtonProps>

export function UnavailableAskCopilotButton() {
  return (
    <Tooltip aria-label="Copilot is not available for this pull request">
      <Button {...askCopilotButtonProps} disabled />
    </Tooltip>
  )
}

export const ErrorAskCopilotButton = memo(function ErrorAskCopilotButton() {
  return (
    <Tooltip aria-label="Copilot failed to load">
      <Button {...askCopilotButtonProps} disabled />
    </Tooltip>
  )
})

export const LoadingAskCopilotButton = memo(function LoadingAskCopilotButton() {
  return (
    <Tooltip aria-label="Loading Copilot features…">
      <Button {...askCopilotButtonProps} disabled />
    </Tooltip>
  )
})
