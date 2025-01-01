import {afterEach, beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {TopicFeedsToastTriggerElement} from '../topic-feeds-toast-trigger-element'

describe('topic-feeds-toast-trigger-element', () => {
  let container: TopicFeedsToastTriggerElement

  beforeEach(async () => {
    container = await fixture(html`
      <topic-feeds-toast-trigger data-topic-display-name="Node JS" data-topic-name="nodejs">
        <button>Star</button>
      </topic-feeds-toast-trigger>

      <template hidden class="js-topic-feeds-toast">
        <div class="Toast">
          <span class="toast-message">{topic_display_name}</span>

          <a href="/dashboard?topic=%7Btopic_name%7D">Go to feed</a>
        </div>
      </template>
    `)
  })

  afterEach(() => {
    document.querySelector('div .Toast')?.remove()
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, TopicFeedsToastTriggerElement)
    assert.equal(container.topicDisplayName, 'Node JS')
    assert.equal(container.topicName, 'nodejs')
  })
})
