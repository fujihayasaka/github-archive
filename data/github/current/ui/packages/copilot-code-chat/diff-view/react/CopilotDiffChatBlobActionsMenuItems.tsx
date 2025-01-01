import type {FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {CopilotIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {DiffLinesDiscussMenuItem} from '../shared/DiffLinesDiscussMenuItem'

export interface CopilotDiffChatBlobActionsMenuItemsProps {
  copilotChatReference: FileDiffReference
}

// actual contents
export const CopilotDiffChatBlobActionsMenuItems: React.FC<CopilotDiffChatBlobActionsMenuItemsProps> = props => (
  <>
    <ActionList.Divider />
    <DiffLinesDiscussMenuItem
      eventContext={{prx: true}}
      leadingVisual={<CopilotIcon />}
      fileDiffReference={props.copilotChatReference}
    />
  </>
)
