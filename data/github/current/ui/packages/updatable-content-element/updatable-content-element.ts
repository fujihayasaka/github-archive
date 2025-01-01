import {controller} from '@github/catalyst'
import {makeSocketMessageHandler} from '@github-ui/alive-socket-channel'
import {updateContent} from '@github-ui/updatable-content'

const handleSocketMessage = makeSocketMessageHandler(async el => {
  return await updateContent(el, {activateScripts: true})
})

@controller
export class UpdatableContentElement extends HTMLElement {
  connectedCallback() {
    this.classList.add('js-socket-channel')
    this.addEventListener('socket:message', handleSocketMessage)
  }

  disconnectedCallback() {
    this.removeEventListener('socket:message', handleSocketMessage)
  }
}
