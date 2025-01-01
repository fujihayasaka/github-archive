import type {FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {LineRange} from '@github-ui/diff-lines'
import {CopilotIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {useMemo} from 'react'
import {DiffLinesAttachMenuItem} from '../shared/DiffLinesAttachMenuItem'
import {DiffLinesDiscussMenuItem} from '../shared/DiffLinesDiscussMenuItem'
import {DiffLinesExplainMenuItem} from '../shared/DiffLinesExplainMenuItem'

export interface CopilotDiffChatContextMenuProps {
  fileDiffReference: FileDiffReference
  selectedRange?: LineRange
  showDivider?: boolean
}

// actual contents
export const CopilotDiffChatContextMenu: React.FC<CopilotDiffChatContextMenuProps> = ({
  fileDiffReference,
  selectedRange,
  showDivider,
}) => {
  const referenceWithRange = useMemo(() => {
    const ref = {...fileDiffReference}
    if (selectedRange) {
      ref.selectedRange = {
        start: `${selectedRange?.startOrientation[0]?.toUpperCase() ?? ''}${selectedRange?.startLineNumber}`,
        end: `${selectedRange?.endOrientation[0]?.toUpperCase() ?? ''}${selectedRange?.endLineNumber}`,
      }
    }
    return ref
  }, [fileDiffReference, selectedRange])

  return (
    <>
      <ActionMenu>
        <ActionMenu.Anchor>
          <ActionList.Item>
            <ActionList.LeadingVisual>
              <CopilotIcon />
            </ActionList.LeadingVisual>
            Copilot
          </ActionList.Item>
        </ActionMenu.Anchor>

        <ActionMenu.Overlay>
          <ActionList>
            <DiffLinesDiscussMenuItem fileDiffReference={referenceWithRange} eventContext={{prx: true}} />
            <DiffLinesExplainMenuItem fileDiffReference={referenceWithRange} eventContext={{prx: true}} />
            <DiffLinesAttachMenuItem fileDiffReference={referenceWithRange} eventContext={{prx: true}} />
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
      {showDivider && <ActionList.Divider />}
    </>
  )
}
