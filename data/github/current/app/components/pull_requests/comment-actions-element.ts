import {controller, target} from '@github/catalyst'
import {publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'
import {CopilotChatIntents} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {sendEvent} from '@github-ui/hydro-analytics'

/**
 * Controller to handle JS behavior for the <comment-actions> element, located in the CommentActionsComponent (a view component).
 */
@controller
export class CommentActionsElement extends HTMLElement {
  @target button: HTMLButtonElement | undefined

  // Opens copilot chat with a prefilled prompt if the CopilotChatAction button is engaged
  openCopilotChat() {
    const chatPrompt = this.button?.getAttribute('data-copilot-prompt')
    if (chatPrompt) {
      publishOpenCopilotChat({
        intent: CopilotChatIntents.conversation,
        content: chatPrompt,
      })
      sendEvent('comment_action.click', {target: 'copilot_chat_button'})
    }
  }
}
