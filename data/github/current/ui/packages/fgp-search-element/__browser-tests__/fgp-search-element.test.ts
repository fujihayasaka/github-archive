import {afterEach, beforeEach, describe, it, assert, fixture, html, waitUntil} from '@github-ui/browser-tests'
import {FgpSearchElement} from '../fgp-search-element'
import {http} from 'msw'
import {setupWorker, type SetupWorker} from 'msw/browser'

const MOCK_FGP_METADATA = {
  test: {label: 'Test', description: 'Test Description', category: 'Test Category'},
  repo_fgp: {
    label: 'Repo FGP',
    description: 'Repo FGP Description',
    category: 'Repo FGP Category',
    base_role: 'read',
  },
  triage_fgp: {
    label: 'Triage FGP',
    description: 'Triage FGP Description',
    category: 'Triage FGP Category',
    base_role: 'triage',
  },
}

describe('fgp-search-container', () => {
  let worker: SetupWorker
  let fgpDataLoaded = false

  const setupFixture = async (): Promise<FgpSearchElement> => {
    return fixture(html`
      <fgp-search data-src="/dummy-src" data-fgp-counter-id="org-permissions-counter">
        <div id="org-permissions-counter">0</div>
        <template data-target="fgp-search.fgpSummaryItemTemplate">
          <li class="js-fgp-list-item">
            <p class="js-fgp-item-title"></p>
            <button class="js-fgp-remove-button" data-action="click:fgp-search#removeFgp">
            <p class="js-repository-inherit-label"></p>
          </li>
        </template>
        <filter-input aria-owns="org-permissions-list">
          <input
            type="text"
            data-target="fgp-search.searchInput"
            data-action="focusin:fgp-search#openSearch blur:fgp-search#closeSearch"
          />
        </filter-input>
        <div
          id="org-permissions-list"
          data-target="fgp-search.resultList"
          data-action="mousedown:fgp-search#keepOpen"
          hidden
        >
          <label>
            <input
              id="checkbox"
              type="checkbox"
              value="test"
              role="option"
              data-action="change:fgp-search#handleFgpChange"
            />
          </label>
          <div id="empty-state" data-filter-empty-state hidden></div>
        </div>
        <div data-target="fgp-search.emptyState">
          <div>
            <h3 data-target="fgp-search.emptyStateHeaderText"></h3>
            <span data-target="fgp-search.emptyStateSubheaderText"></span>
          </div>
        </div>
        <ul data-target="fgp-search.fgpSummaryList" hidden></ul>
      </fgp-search>
    `)
  }

  beforeEach(async function () {
    worker = setupWorker(
      http.get('/dummy-src', () => {
        return new Response(JSON.stringify(MOCK_FGP_METADATA))
      }),
    )
    worker.events.on('response:mocked', () => {
      fgpDataLoaded = true
    })

    await worker.start()
  })

  afterEach(() => {
    fgpDataLoaded = false
    worker.stop()
  })

  it('isConnected', async () => {
    const container = await setupFixture()

    assert.isTrue(container.isConnected)
    assert.instanceOf(container, FgpSearchElement)
  })

  it('filter input opens and closes', async () => {
    const container = await setupFixture()

    assert.isTrue(container.resultList.hidden)
    container.openSearch()
    assert.isFalse(container.resultList.hidden)
    container.closeSearch()
    assert.isTrue(container.resultList.hidden)
  })

  it('clicking on checkbox adds and removes fgp from summary', async () => {
    const container = await setupFixture()
    await waitUntil(() => fgpDataLoaded, 'expected FGP metadata response to be completed')

    const checkbox = container.querySelector('#checkbox') as HTMLInputElement
    assert.isFalse(container.emptyState.hidden)
    assert.isTrue(container.fgpSummaryList.hidden)

    checkbox.click()
    assert.isTrue(container.emptyState.hidden)
    assert.isFalse(container.fgpSummaryList.hidden)
    assert.equal(container.querySelector('#org-permissions-counter')!.textContent, '1')

    checkbox.click()
    assert.isFalse(container.emptyState.hidden)
    assert.isTrue(container.fgpSummaryList.hidden)
    assert.equal(container.querySelector('#org-permissions-counter')!.textContent, '0')
  })

  it('removes item from summary', async () => {
    const container = await setupFixture()
    await waitUntil(() => fgpDataLoaded, 'expected FGP metadata response to be completed')

    container.addToSummary('test')
    assert.isTrue(container.emptyState.hidden)
    assert.isFalse(container.fgpSummaryList.hidden)

    container.removeFromSummary('test')
    assert.isFalse(container.emptyState.hidden)
    assert.isTrue(container.fgpSummaryList.hidden)
  })

  it('adds cached fgps to summary', async () => {
    const container: FgpSearchElement = await fixture(html`
      <fgp-search
        data-src="/dummy-src"
        data-fgp-counter-id="org-permissions-counter"
        data-initial-edit-role-permissions=${JSON.stringify(['test'])}
      >
        <div id="org-permissions-counter">0</div>
        <template data-target="fgp-search.fgpSummaryItemTemplate">
          <li class="js-fgp-list-item">
            <p class="js-fgp-item-title"></p>
            <button class="js-fgp-remove-button" data-action="click:fgp-search#removeFgp">
            <p class="js-repository-inherit-label"></p>
          </li>
        </template>
        <filter-input aria-owns="org-permissions-list">
          <input
            type="text"
            data-target="fgp-search.searchInput"
            data-action="focusin:fgp-search#openSearch blur:fgp-search#closeSearch"
          />
        </filter-input>
        <div id="org-permissions-list" data-target="fgp-search.resultList" data-action="mousedown:fgp-search#keepOpen" hidden>
          <label>
            <input id="checkbox" type="checkbox" value="test" role="option" data-action="change:fgp-search#handleFgpChange" checked/>
          </label>
          <div id="empty-state" data-filter-empty-state hidden></div>
        </div>
        <div data-target="fgp-search.emptyState">
          <div>
            <h3 data-target="fgp-search.emptyStateHeaderText"></h3>
            <span data-target="fgp-search.emptyStateSubheaderText"></span>
          </div>
        </div>
        <ul data-target="fgp-search.fgpSummaryList" hidden></ul>
      </fgp-search>
    `)

    await waitUntil(() => fgpDataLoaded, 'expected FGP metadata response to be completed')
    await new Promise(res => setTimeout(res, 10))

    assert.isTrue(container.emptyState.hidden)
    assert.isFalse(container.fgpSummaryList.hidden)
    assert.equal(container.querySelector('#org-permissions-counter')!.textContent, '1')
    assert.equal(container.fgpSummaryList.querySelectorAll('.js-fgp-list-item').length, 1)
    assert.equal(container.fgpSummaryList.querySelector('.js-fgp-item-title')!.textContent, 'Test Description')
  })

  describe('repo permissions selector', () => {
    const setupRepoFixture = async (): Promise<FgpSearchElement> => {
      return fixture(html`
      <fgp-search
        data-src="/dummy-src"
        data-fgp-counter-id="repo-permissions-counter"
        data-initial-edit-role-permissions=${JSON.stringify([])}
      >
        <div id="repo-permissions-counter">0</div>
        <template data-target="fgp-search.fgpSummaryItemTemplate">
          <li class="js-fgp-list-item">
            <p class="js-fgp-item-title"></p>
            <button class="js-fgp-remove-button" data-action="click:fgp-search#removeFgp">
            <p class="js-repository-inherit-label"></p>
          </li>
        </template>
        <filter-input aria-owns="repo-permissions-list">
          <input
            type="text"
            data-target="fgp-search.searchInput"
            data-action="focusin:fgp-search#openSearch blur:fgp-search#closeSearch"
            disabled
          />
        </filter-input>
        <div data-target="fgp-search.baseRoleSelect" data-action="change:fgp-search#handleRepoBaseRoleChange">
          <button data-value="none">None</button>
          <button data-value="read">Read</button>
          <button data-value="triage">Triage</button>
          <button data-value="write">Write</button>
          <button data-value="admin">Admin</button>
        </div>
        <div id="repo-permissions-list" data-target="fgp-search.resultList" data-action="mousedown:fgp-search#keepOpen" hidden>
          <label>
            <input id="checkbox" type="checkbox" value="test" role="option" data-action="change:fgp-search#handleFgpChange"/>
            <input id="checkbox" type="checkbox" value="repo_fgp" role="option" data-action="change:fgp-search#handleFgpChange"/>
          </label>
          <div id="empty-state" data-filter-empty-state hidden></div>
        </div>
        <div data-target="fgp-search.emptyState">
          <div>
            <h3 data-target="fgp-search.emptyStateHeaderText">Choose a repository role to inherit</h3>
            <span data-target="fgp-search.emptyStateSubheaderText">You can only add repository permissions once a base repository role is selected.</span>
          </div>
        </div>
        <ul data-target="fgp-search.fgpSummaryList" hidden></ul>
      </fgp-search>
    `)
    }

    it('input is only enabled when base role is selected', async () => {
      const container = await setupRepoFixture()
      await waitUntil(() => fgpDataLoaded, 'expected FGP metadata response to be completed')

      assert.isTrue(container.searchInput.disabled)

      // Simulate clicking on the read option
      const readOption = container.baseRoleSelect.querySelector<HTMLButtonElement>('button[data-value="read"]')!
      readOption.ariaChecked = 'true'
      container.handleRepoBaseRoleChange()

      assert.isFalse(container.searchInput.disabled)
    })

    it('selecting a (non-read) base role adds inherited fgps', async () => {
      const container = await setupRepoFixture()
      await waitUntil(() => fgpDataLoaded, 'expected FGP metadata response to be completed')

      // Simulate clicking on the read option
      const triageOption = container.baseRoleSelect.querySelector<HTMLButtonElement>('button[data-value="triage"]')!
      triageOption.ariaChecked = 'true'
      container.handleRepoBaseRoleChange()

      assert.isFalse(container.fgpSummaryList.hidden)
      assert.equal(container.querySelector('#repo-permissions-counter')!.textContent, '1')
      assert.equal(container.fgpSummaryList.querySelectorAll('.js-fgp-list-item').length, 1)
      assert.equal(container.fgpSummaryList.querySelector('.js-fgp-item-title')!.textContent, 'Repo FGP Description')
    })

    it('selecting the read base role changes the empty state text', async () => {
      const container = await setupRepoFixture()
      await waitUntil(() => fgpDataLoaded, 'expected FGP metadata response to be completed')

      assert.isTrue(container.fgpSummaryList.hidden)
      assert.isFalse(container.emptyState.hidden)
      assert.equal(container.emptyStateHeaderText.textContent, 'Choose a repository role to inherit')
      assert.equal(
        container.emptyStateSubheaderText.textContent,
        'You can only add repository permissions once a base repository role is selected.',
      )

      // Simulate clicking on the read option
      const readOption = container.baseRoleSelect.querySelector<HTMLButtonElement>('button[data-value="read"]')!
      readOption.ariaChecked = 'true'
      container.handleRepoBaseRoleChange()

      assert.isTrue(container.fgpSummaryList.hidden)
      assert.isFalse(container.emptyState.hidden)
      assert.equal(container.emptyStateHeaderText.textContent, 'No permissions added yet')
      assert.equal(container.emptyStateSubheaderText.textContent, 'Get started by adding permissions to this role.')
    })
  })
})
