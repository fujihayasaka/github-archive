import {controller, target} from '@github/catalyst'
import {debounce} from '@github/mini-throttle'
import {activate as navigationActivate, focus as navigationFocus} from '@github-ui/input-navigation-behavior'
import {fuzzyHighlightElement} from '@github-ui/fuzzy-filter'
import {requestSubmit} from '@github-ui/form-utils'
import type {Suggestion} from './model'
import {buildSearchURL, getSuggestions, updateSearchURL} from './model'
import type {PageViews} from './page-views'
import {logPageView, getPageViewsMap, scorer} from './page-views'
import {trackJumpToEvent, trackSelection, updateCurrentEventPayload} from './tracking'
import {filterSuggestions} from './filtering'

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace JSX {
    interface IntrinsicElements {
      'jump-to': CustomElement<typeof JumpToElement>
    }
  }
}

@controller
export class JumpToElement extends HTMLElement {
  @target form: HTMLFormElement | undefined
  @target field: HTMLInputElement | undefined
  @target suggestionsContainer: HTMLElement | undefined
  @target resultsContainer: HTMLElement | undefined
  @target suggestionsTemplate: HTMLElement | undefined
  @target noResultsTemplate: HTMLElement | undefined

  connectedCallback() {
    // add current page to recently visited list for jump-to
    logPageView(window.location.pathname)

    /*
      This is an event that is used by Blackbird search to open the search dialog and append a query
      to the current search input in response to various actions in the app.

      However, when Blackbird is disabled (as it is in GHES), we still want to preserve some of that intended behavior
      by focusing the Jump To search input when the event is triggered.

      Without this, the "/" hotkey will not work to activate the Jump To search input on certain pages (such as repository file trees).
    */
    window.addEventListener('blackbird_monolith_append_and_focus_input', this.handleFocusInputEvent)
  }

  disconnectedCallback() {
    window.removeEventListener('blackbird_monolith_append_and_focus_input', this.handleFocusInputEvent)
  }

  get queryText() {
    return this.field?.value.trim() ?? ''
  }

  get suggestionsUrl() {
    return this.field?.getAttribute('data-jump-to-suggestions-path')
  }

  #asyncSuggestions: Promise<Suggestion[]> | null = null
  async asyncSuggestions() {
    if (!this.field) return []
    if (!this.#asyncSuggestions) {
      this.#asyncSuggestions = getSuggestions(this.field)
    }
    return this.#asyncSuggestions
  }

  handleInput = debounce(async () => {
    this.updateSearchEntries()
    this.enableNavigation()
    this.populateDropdown(await this.asyncSuggestions())
  }, 100)

  // ensures that the dropdown stays open if any child element of jump-to as a whole
  // has focus, this allows screenreaders to navigate the list
  #focusTimeout: number | null = null

  handleFocusIn = () => {
    if (this.#focusTimeout) window.clearTimeout(this.#focusTimeout)
    this.activateSearchField()
    this.showDropdown()
    this.handleInput()
  }

  handleFocusOut = () => {
    this.deactivateSearchField()
    this.#focusTimeout = window.setTimeout(() => {
      this.hideDropdown()
    }, 0)
  }

  handleSubmit = () => {
    if (this.form?.getAttribute('data-scoped-search-url')) {
      updateCurrentEventPayload({})
    }
    trackJumpToEvent('search')
  }

  handleNavigationKeydown = (event: CustomEvent) => {
    const {currentTarget, detail} = event
    const hotkey = detail?.hotkey
    if (!(currentTarget instanceof HTMLElement)) return
    const selection = currentTarget.querySelector('.js-navigation-item.navigation-focus')

    switch (hotkey) {
      case 'Enter':
        if (!selection) {
          if (this.form) requestSubmit(this.form)
        } else {
          // Otherwise, track the selection event.
          const pathEl = selection.querySelector<HTMLElement>('.js-jump-to-suggestion-path')
          if (pathEl && this.form) trackSelection(pathEl, this.form)
        }
        break
      case 'Escape':
        // eslint-disable-next-line github/no-blur
        this.field?.blur()
        this.hideDropdown()
        break
    }
  }

  handleNavigationFocus = (event: CustomEvent) => {
    const id = (event.target as Element).id
    const items = this.resultsContainer?.querySelectorAll('.js-navigation-item') || []
    for (const item of items) {
      item.setAttribute('aria-selected', (event.target === item).toString())
    }
    this.field?.setAttribute('aria-activedescendant', id)
  }

  // Handle selecting an item from the suggestion list
  handleSuggestionClick = (event: Event) => {
    const link = event.currentTarget as HTMLAnchorElement

    // If it's a mousedown event, prevent default to avoid losing focus
    // but allow the click event to proceed naturally for navigation
    if (event.type === 'mousedown') {
      event.preventDefault()
      return
    }

    // Ensure we have an up-to-date search q param on the search suggestion link on click
    if (link.getAttribute('data-target-type') === 'Search') {
      link.href = updateSearchURL(this.queryText, link.href)
    }
    this.hideDropdown()
    this.deactivateSearchField()
    // Track click events
    if (this.form) trackSelection(link, this.form)
  }

  updateSearchEntries() {
    if (!this.field) return
    const form = this.field.form
    const queryText = this.field.value.trim()
    const isScoped = !!(this.field.form && this.field.form.getAttribute('data-scope-type'))
    const hasOwnerScope = (this.field.form && this.field.form.getAttribute('data-scope-type')) === 'Repository'
    const existingScopedSearch = this.resultsContainer?.querySelector<HTMLElement>('.js-jump-to-scoped-search')
    const existingOwnerScopedSearch = this.resultsContainer?.querySelector<HTMLElement>(
      '.js-jump-to-owner-scoped-search',
    )
    const existingGlobalSearch = this.resultsContainer?.querySelector<HTMLElement>('.js-jump-to-global-search')

    // hide scoped search if no query text or not a scoped page
    /* eslint-disable-next-line github/no-d-none */
    existingScopedSearch?.classList.toggle('d-none', !queryText || !isScoped)
    if (existingOwnerScopedSearch) {
      /* eslint-disable-next-line github/no-d-none */
      existingOwnerScopedSearch.classList.toggle('d-none', !queryText || !hasOwnerScope)
    }
    // hide global search if no query text
    /* eslint-disable-next-line github/no-d-none */
    existingGlobalSearch?.classList.toggle('d-none', !queryText)

    // update scoped search entry if we are showing it
    if (queryText && isScoped) {
      const searchPath = form?.getAttribute('action')
      const updatedScopedSearch = this.updateSearchEntry(
        existingScopedSearch ? existingScopedSearch : new HTMLElement(),
        queryText,
        buildSearchURL(searchPath ? searchPath : '', queryText),
        true,
        false,
      )
      this.resultsContainer?.replaceChild(
        updatedScopedSearch,
        existingScopedSearch ? existingScopedSearch : new HTMLElement(),
      )
    }

    if (existingOwnerScopedSearch) {
      if (queryText && isScoped) {
        const searchPath = form?.getAttribute('data-owner-scoped-search-url')
        const updatedOwnerScopedSearch = this.updateSearchEntry(
          existingOwnerScopedSearch,
          queryText,
          buildSearchURL(searchPath ? searchPath : '', queryText),
          true,
          true,
        )
        this.resultsContainer?.replaceChild(updatedOwnerScopedSearch, existingOwnerScopedSearch)
      }
    }

    // // update global search
    if (queryText) {
      const unscopedSearchPath = form?.getAttribute('data-unscoped-search-url')
      const updatedGlobalSearch = this.updateSearchEntry(
        existingGlobalSearch ? existingGlobalSearch : new HTMLElement(),
        queryText,
        buildSearchURL(unscopedSearchPath ? unscopedSearchPath : '', queryText),
        false,
        false,
      )
      this.resultsContainer?.replaceChild(
        updatedGlobalSearch,
        existingGlobalSearch ? existingGlobalSearch : new HTMLElement(),
      )
    }
  }

  updateSearchEntry(
    element: HTMLElement,
    queryText: string,
    href: string,
    isScoped: boolean,
    isOwnerScoped: boolean,
  ): HTMLElement {
    const el = element.cloneNode(true) as HTMLElement

    if (isScoped) {
      el.id = `jump-to-suggestion-search-${isOwnerScoped ? 'scoped-owner' : 'scoped'}`
    } else {
      el.id = `jump-to-suggestion-search-global`
    }

    const anchor = el.querySelector<HTMLAnchorElement>('.js-jump-to-suggestion-path')
    if (anchor) {
      anchor.href = href
      anchor.setAttribute('data-target-type', 'Search')
    }

    const nameElement = el.querySelector<HTMLElement>('.js-jump-to-suggestion-name')
    if (nameElement) {
      nameElement.textContent = queryText
      nameElement.setAttribute('aria-label', queryText)
    }

    this.showSuggestionOcticon(el, '.js-jump-to-octicon-search')

    const badgeEl = el.querySelector<HTMLElement>('.js-jump-to-badge-search')
    if (badgeEl) {
      /* eslint-disable-next-line github/no-d-none */
      badgeEl.classList.remove('d-none')
      if (isScoped) {
        /* eslint-disable-next-line github/no-d-none */
        badgeEl.querySelector<HTMLElement>('.js-jump-to-badge-search-text-default')?.classList.remove('d-none')
      } else {
        /* eslint-disable-next-line github/no-d-none */
        badgeEl.querySelector<HTMLElement>('.js-jump-to-badge-search-text-global')?.classList.remove('d-none')
      }
    }

    return el
  }

  enableNavigation() {
    if (!this.resultsContainer) return
    if (this.queryText) {
      navigationFocus(this.resultsContainer)
    } else {
      navigationActivate(this.resultsContainer)
    }
  }

  populateDropdown(suggestions: Suggestion[]): void {
    const matchingSuggestions = rank(
      filterSuggestions(suggestions, this.queryText, window.location.pathname),
      getPageViewsMap(),
    )
    const suggestionsToDisplay = matchingSuggestions.slice(0, 7)

    updateCurrentEventPayload({
      result_count: matchingSuggestions.length.toString(),
      display_count: suggestionsToDisplay.length.toString(),
      filter_count: (suggestions.length - matchingSuggestions.length).toString(),
      queryText: this.queryText,
      display_set: JSON.stringify(suggestionsToDisplay.map(s => [s.type, s.databaseId])),
    })

    this.updateDropdown(suggestionsToDisplay)
    if (!trackJumpToEvent('menu-activation')) {
      trackJumpToEvent('query')
    }
  }

  updateDropdown(suggestionsToDisplay: Suggestion[]) {
    const form = this.field?.form
    if (!form || !this.suggestionsTemplate) return

    const results = document.createDocumentFragment()

    if (suggestionsToDisplay.length < 1 && !this.queryText) {
      this.displayNoResults()
    } else {
      const template = this.suggestionsTemplate.firstElementChild as HTMLLIElement | null
      if (!template) return
      for (const [i, suggestion] of suggestionsToDisplay.entries()) {
        results.appendChild(this.fillTemplate(template, suggestion, this.queryText, i))
      }

      this.replaceSuggestions(results)
    }
  }

  displayNoResults() {
    if (!isUserLoggedIn() || !this.noResultsTemplate) return
    const template = this.noResultsTemplate.firstElementChild as HTMLLIElement | null
    if (!template) return

    const noResults = template.cloneNode(true)
    if (noResults instanceof HTMLElement) {
      /* eslint-disable-next-line github/no-d-none */
      noResults.classList.remove('d-none')
    }

    this.replaceSuggestions(noResults)
  }

  replaceSuggestions(newSuggestions: Node) {
    if (!this.resultsContainer) return

    for (const oldResult of this.resultsContainer.querySelectorAll('.js-jump-to-suggestion')) {
      oldResult.parentNode?.removeChild(oldResult)
    }

    this.resultsContainer.appendChild(newSuggestions)
  }

  fillTemplate(template: HTMLElement, suggestion: Suggestion, queryText: string, clientRank: number): HTMLElement {
    const el = template.cloneNode(true) as HTMLElement
    el.id = `jump-to-suggestion-${suggestion.type.toLowerCase()}-${suggestion.databaseId}`

    const anchor = el.querySelector<HTMLAnchorElement>('.js-jump-to-suggestion-path')
    if (anchor) {
      anchor.href = suggestion.path
      anchor.setAttribute('data-target-type', suggestion.type)

      anchor.setAttribute('data-target-id', `${suggestion.databaseId}`)
      anchor.setAttribute('data-client-rank', `${clientRank}`)
      anchor.setAttribute('data-server-rank', `${suggestion.rank}`)
    }

    const nameElement = el.querySelector<HTMLElement>('.js-jump-to-suggestion-name')
    if (nameElement) {
      nameElement.textContent = suggestion.name
      // set this because the element fuzzyhighlighting confuses screenreaders
      nameElement.setAttribute('aria-label', suggestion.name)
    }

    fuzzyHighlightElement(nameElement ? nameElement : new Element(), queryText.replace(/\s/g, ''))

    switch (suggestion.type) {
      case 'Team': {
        const avatar = el.querySelector<HTMLImageElement>('.js-jump-to-suggestion-avatar')
        if (avatar) {
          avatar.alt = suggestion.name
          avatar.src = suggestion.avatarUrl ? suggestion.avatarUrl : ''
          /* eslint-disable-next-line github/no-d-none */
          avatar.classList.remove('d-none')
        }
        break
      }
      case 'Project':
        this.showSuggestionOcticon(el, '.js-jump-to-octicon-project')
        break
      case 'Repository':
        this.showSuggestionOcticon(el, '.js-jump-to-octicon-repo')
        break
    }

    const badgeEl = el.querySelector<HTMLElement>('.js-jump-to-badge-jump')
    /* eslint-disable-next-line github/no-d-none */
    badgeEl?.classList.remove('d-none')

    return el
  }

  showSuggestionOcticon(el: HTMLElement, octiconSelector: string) {
    const octiconContainer = el.querySelector<HTMLElement>('.js-jump-to-octicon')
    const octicon = octiconContainer?.querySelector<SVGElement>(octiconSelector)
    /* eslint-disable-next-line github/no-d-none */
    octiconContainer?.classList.remove('d-none')
    /* eslint-disable-next-line github/no-d-none */
    octicon?.classList.remove('d-none')
  }

  activateSearchField() {
    this.field?.classList.add('js-navigation-enable')
    this.field?.classList.add('jump-to-field-active')
    this.field?.parentElement?.classList.add('search-wrapper-suggestions-active')
  }

  deactivateSearchField() {
    this.field?.classList.remove('js-navigation-enable')
    this.field?.classList.remove('jump-to-field-active')
    this.field?.parentElement?.classList.remove('search-wrapper-suggestions-active')
  }

  showDropdown() {
    /* eslint-disable-next-line github/no-d-none */
    this.suggestionsContainer?.classList.remove('d-none')
    this.field?.classList.add('jump-to-dropdown-visible')
    this.field?.setAttribute('aria-expanded', 'true')
  }

  hideDropdown() {
    /* eslint-disable-next-line github/no-d-none */
    this.suggestionsContainer?.classList.add('d-none')
    this.field?.classList.remove('jump-to-dropdown-visible')
    this.field?.setAttribute('aria-expanded', 'false')
    trackJumpToEvent('menu-deactivation')
  }

  handleFocusInputEvent = () => {
    this.field?.focus()
  }
}

function rank(suggestions: Suggestion[], pageViews: PageViews): Suggestion[] {
  const scorePage = scorer(pageViews)
  return suggestions.sort((a, b) => scorePage(b.pageKey) - scorePage(a.pageKey))
}

function isUserLoggedIn(): boolean {
  return Boolean(document.head?.querySelector<HTMLMetaElement>('meta[name="user-login"]')?.content)
}
