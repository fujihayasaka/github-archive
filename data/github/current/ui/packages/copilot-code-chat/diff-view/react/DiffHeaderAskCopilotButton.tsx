import {publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'
import {CopilotChatIntents, type FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {sendEvent} from '@github-ui/hydro-analytics'
import {CopilotIcon, TriangleDownIcon} from '@primer/octicons-react'
import {Button, type ButtonProps} from '@primer/react'
import {memo} from 'react'
import {UnavailableAskCopilotButton} from '../shared/DiffHeaderAskCopilotButton'
import styles from '../shared/DiffHeaderAskCopilotButton.module.css'
import type {DiffEntryData} from '../shared/use-get-diff-entry-data'
import {AskCopilotDiffEntriesSelectPanel} from './AskCopilotDiffEntriesSelectPanel'
import {copilotChatPanelID, copilotDiffHeaderButtonID} from '@github-ui/copilot-chat/utils/constants'

const askCopilotButtonProps = {
  id: copilotDiffHeaderButtonID,
  size: 'small',
  leadingVisual: CopilotIcon,
  children: 'Ask Copilot',
  trailingVisual: TriangleDownIcon,
  className: styles.askCopilotButton,
  'aria-controls': copilotChatPanelID,
  'aria-expanded': false,
} as const satisfies Partial<ButtonProps>

export interface DiffHeaderAskCopilotButtonProps {
  entriesData: DiffEntryData[]
}

const submitConversationReferences = (references: FileDiffReference[]) => {
  publishOpenCopilotChat({
    id: copilotDiffHeaderButtonID,
    intent: CopilotChatIntents.conversation,
    references,
  })
  sendEvent('copilot.file-diff-header.discuss')
}

export const DiffHeaderAskCopilotButton = memo(function CopilotChatDiffHeaderButton({
  entriesData,
}: DiffHeaderAskCopilotButtonProps) {
  if (entriesData.length === 0) return <UnavailableAskCopilotButton />
  if (entriesData.length === 1) {
    return <SingleFileAskCopilotButton diffEntry={entriesData[0]} onSubmit={submitConversationReferences} />
  }

  return (
    <AskCopilotDiffEntriesSelectPanel
      diffEntries={entriesData}
      anchorProps={askCopilotButtonProps}
      onSubmit={submitConversationReferences}
    />
  )
})

interface SingleFileAskCopilotButtonProps {
  diffEntry?: DiffEntryData
  onSubmit: (references: FileDiffReference[]) => void
}

const SingleFileAskCopilotButton: React.FC<SingleFileAskCopilotButtonProps> = ({diffEntry, onSubmit}) => {
  // if we only have one item, and that item is not copilotable, there's nothing we can do here but throw to put the
  // button into an error state
  if (diffEntry?.reference === undefined) {
    return <UnavailableAskCopilotButton />
  }

  return (
    <Button
      {...askCopilotButtonProps}
      onClick={() => onSubmit([diffEntry.reference as FileDiffReference])}
      trailingVisual={null}
    />
  )
}
