import {publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'
import {CopilotChatIntents, type FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {sendEvent} from '@github-ui/hydro-analytics'
import {CopilotIcon, TriangleDownIcon} from '@primer/octicons-react'
import {Button, type ButtonProps} from '@primer/react'
import {memo} from 'react'
import {LoadingAskCopilotButton, UnavailableAskCopilotButton} from '../shared/DiffHeaderAskCopilotButton'
import {AskCopilotDiffEntriesSelectPanel} from './AskCopilotDiffEntriesSelectPanel'
import {useGetDiffEntryData} from './DiffEntriesList'

const askCopilotButtonProps = {
  size: 'small',
  leadingVisual: CopilotIcon,
  className: 'mr-2',
  children: 'Ask Copilot',
  trailingVisual: TriangleDownIcon,
} as const satisfies Partial<ButtonProps>

export interface DiffHeaderAskCopilotButtonProps {
  copilotAccessAllowed: boolean
  entriesCount: number
  pullRequestId: string
}

export const DiffHeaderAskCopilotButton = memo(function CopilotChatDiffHeaderButton({
  copilotAccessAllowed,
  entriesCount,
  pullRequestId,
}: DiffHeaderAskCopilotButtonProps) {
  const onSubmit = (references: FileDiffReference[]) => {
    publishOpenCopilotChat({
      intent: CopilotChatIntents.conversation,
      references,
    })
    sendEvent('copilot.file-diff-header.discuss')
  }

  if (!copilotAccessAllowed) {
    return null
  }

  if (entriesCount === 0) {
    return <UnavailableAskCopilotButton />
  }
  if (entriesCount === 1) {
    return <SingleFileAskCopilotButton pullRequestId={pullRequestId} onSubmit={onSubmit} />
  }
  return (
    <AskCopilotDiffEntriesSelectPanel
      anchorProps={askCopilotButtonProps}
      onSubmit={onSubmit}
      pullRequestId={pullRequestId}
    />
  )
})

interface SingleFileAskCopilotButtonProps {
  pullRequestId: string
  onSubmit: (references: FileDiffReference[]) => void
}

function SingleFileAskCopilotButton({onSubmit, pullRequestId}: SingleFileAskCopilotButtonProps) {
  const {entriesData, loading} = useGetDiffEntryData(pullRequestId)

  if (loading) {
    return <LoadingAskCopilotButton />
  }

  // if we only have one item, and that item is not copilotable, there's nothing we can do here but throw to put the
  // button into an error state
  if (entriesData[0]?.reference === undefined) {
    return <UnavailableAskCopilotButton />
  }

  return (
    <Button
      {...askCopilotButtonProps}
      onClick={() => onSubmit([entriesData[0]?.reference as FileDiffReference])}
      trailingVisual={null}
    />
  )
}
