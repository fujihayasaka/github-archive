import {publishAddCopilotChatReference, publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'
import {CopilotChatIntents, type FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {sendEvent} from '@github-ui/hydro-analytics'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'

interface CopilotChatDiffMenuItemProps {
  fileDiffReference: FileDiffReference | undefined
}

/**
 * Menu items that get injected into Rails diff entry ... action menu
 */
export const DiffEntryMenuItems: React.FC<CopilotChatDiffMenuItemProps> = ({fileDiffReference}) => {
  const {addToast} = useToastContext()

  if (fileDiffReference === undefined) {
    return <BuildMenu inactiveText="Copilot is not available for this file type" />
  }

  const handleDiscuss = () => {
    publishOpenCopilotChat({
      intent: CopilotChatIntents.conversation,
      references: [fileDiffReference],
    })
    sendEvent('copilot.file-diff.menu.discuss')
  }

  const handleAttach = () => {
    publishAddCopilotChatReference(fileDiffReference)
    // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
    addToast({message: 'Reference added to thread', type: 'success'})
    sendEvent('copilot.file-diff.menu.add')
  }

  return <BuildMenu handleAttach={handleAttach} handleDiscuss={handleDiscuss} />
}

interface BuildMenuProps {
  handleDiscuss?: () => void
  handleAttach?: () => void
  inactiveText?: string
}

const BuildMenu = ({handleDiscuss, handleAttach, inactiveText}: BuildMenuProps) => {
  return (
    <>
      <BuildItemForRailsMenu text="Ask Copilot about this diff" onClick={handleDiscuss} inactiveText={inactiveText} />
      <BuildItemForRailsMenu text="Attach to current thread" onClick={handleAttach} inactiveText={inactiveText} />
    </>
  )
}

/**
 * We can't use ActionList.Item in the rails implementation because the menu in Rails is not an ActionList
 * It's a deprecated ActionMenu pattern but we're not going to change that right now
 * Instead we're going to match up the styles and markup using buttons and css
 * see - https://github.com/github/pull-requests/issues/15453
 */
function BuildItemForRailsMenu({onClick, inactiveText, text}: BuildMenuProps & {text: string; onClick?: () => void}) {
  if (inactiveText) {
    return (
      <button type="button" disabled role="menuitem" className="px-5 dropdown-item btn-link" aria-label={inactiveText}>
        {text}
      </button>
    )
  }

  return (
    <button type="button" role="menuitem" className="px-5 dropdown-item btn-link" onClick={onClick}>
      {text}
    </button>
  )
}
