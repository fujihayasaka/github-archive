import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {SecurityAnalysisGhasElement} from '../security-analysis-ghas-element'

describe('security-analysis-ghas-element', () => {
  let container: SecurityAnalysisGhasElement

  beforeEach(async function () {
    container = await fixture(
      html` <security-analysis-ghas>
        <input id="enabled_box" type="checkbox" />
        <input id="disabled_box" type="checkbox" data-action="click:security-analysis-ghas#checkDisabledCheckbox" />
      </security-analysis-ghas>`,
    )
  })

  it('cannot check disabled checkboxes', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, SecurityAnalysisGhasElement)

    const disabledBox = container.querySelector('#disabled_box') as HTMLInputElement
    const enabledBox = container.querySelector('#enabled_box') as HTMLInputElement
    assert.isNotNull(disabledBox)
    assert.isNotNull(enabledBox)

    assert.isFalse(disabledBox.checked)
    assert.isFalse(enabledBox.checked)

    disabledBox.click()
    assert.isFalse(disabledBox.checked)

    // but can click regular checkboxes
    enabledBox.click()
    assert.isTrue(enabledBox.checked)
  })
})
