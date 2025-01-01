import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {ExpandableRoleRowElement} from '../expandable-role-row-element'

describe('expandable-role-row-element', () => {
  let container: ExpandableRoleRowElement

  beforeEach(async function () {
    container = await fixture(html`
      <expandable-role-row>
        <button
          id="showButton"
          data-action="click:expandable-role-row#showDetails"
          data-target="expandable-role-row.showDetailsButton"
        />
        <button
          id="hideButton"
          hidden
          data-action="click:expandable-role-row#hideDetails"
          data-target="expandable-role-row.hideDetailsButton"
        />
        <div id="permissionDetails" hidden data-target="expandable-role-row.permissionDetails" />
      </expandable-role-row>
    `)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, ExpandableRoleRowElement)
  })

  it('toggle visibility', () => {
    const showDetailsButton = container.querySelector('#showButton') as HTMLButtonElement
    const hideDetailsButton = container.querySelector('#hideButton') as HTMLButtonElement
    const permissionDetails = container.querySelector('#permissionDetails') as HTMLElement

    // Assert state before clicking
    assert.isFalse(showDetailsButton.hidden)
    assert.isTrue(hideDetailsButton.hidden)
    assert.isTrue(permissionDetails.hidden)

    showDetailsButton.click()

    // After click, hide button and details section is visible
    assert.isTrue(showDetailsButton.hidden)
    assert.isFalse(hideDetailsButton.hidden)
    assert.isFalse(permissionDetails.hidden)

    // Clicking hide button resets to starting state
    hideDetailsButton.click()
    assert.isFalse(showDetailsButton.hidden)
    assert.isTrue(hideDetailsButton.hidden)
    assert.isTrue(permissionDetails.hidden)
  })
})
