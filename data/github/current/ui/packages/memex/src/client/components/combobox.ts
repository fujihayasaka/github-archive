import {isMacOS} from '@github-ui/get-os'

interface ComboboxOptions {
  tabInsertsSuggestions?: boolean
  firstOptionSelectionMode?: 'none' | 'active' | 'selected'
  scrollIntoViewOptions?: ScrollIntoViewOptions
}

export default class Combobox {
  input: HTMLInputElement
  list: HTMLElement
  tabInsertsSuggestions: boolean
  firstOptionSelectionMode: 'none' | 'active' | 'selected'
  scrollIntoViewOptions: ScrollIntoViewOptions
  isComposing: boolean
  ctrlBindings: boolean
  keyboardEventHandler: (event: KeyboardEvent) => void
  compositionEventHandler: (event: CompositionEvent) => void
  declare inputHandler: () => void

  constructor(
    input: HTMLInputElement,
    list: HTMLElement,
    {
      tabInsertsSuggestions = true,
      firstOptionSelectionMode = 'none',
      scrollIntoViewOptions = {block: 'nearest', inline: 'nearest'},
    }: ComboboxOptions = {},
  ) {
    this.input = input
    this.list = list
    this.tabInsertsSuggestions = tabInsertsSuggestions
    this.firstOptionSelectionMode = firstOptionSelectionMode
    this.scrollIntoViewOptions = scrollIntoViewOptions
    this.isComposing = false

    if (!list.id) {
      list.id = `combobox-${Math.random().toString().slice(2, 6)}`
    }

    // eslint-disable-next-line ssr-friendly/no-dom-globals-in-constructor
    this.ctrlBindings = !!navigator.userAgent.match(/Macintosh/)
    this.keyboardEventHandler = event => keyboardBindings(event, this)
    this.compositionEventHandler = event => trackComposition(event, this)

    input.setAttribute('role', 'combobox')
    input.setAttribute('aria-controls', list.id)
    input.setAttribute('aria-expanded', 'false')
    input.setAttribute('aria-autocomplete', 'list')
    input.setAttribute('aria-haspopup', 'listbox')
  }

  destroy() {
    this.clearSelection()
    this.stop()
    this.input.removeAttribute('role')
    this.input.removeAttribute('aria-controls')
    this.input.removeAttribute('aria-expanded')
    this.input.removeAttribute('aria-autocomplete')
    this.input.removeAttribute('aria-haspopup')
  }

  start() {
    this.input.setAttribute('aria-expanded', 'true')
    this.input.addEventListener('compositionstart', this.compositionEventHandler)
    this.input.addEventListener('compositionend', this.compositionEventHandler)
    this.input.addEventListener('keydown', this.keyboardEventHandler)
    this.list.addEventListener('click', commitWithElement)
    this.resetSelection()
  }

  stop() {
    this.clearSelection()
    this.input.setAttribute('aria-expanded', 'false')
    this.input.removeEventListener('compositionstart', this.compositionEventHandler)
    this.input.removeEventListener('compositionend', this.compositionEventHandler)
    this.input.removeEventListener('keydown', this.keyboardEventHandler)
    this.list.removeEventListener('click', commitWithElement)
  }

  indicateDefaultOption() {
    if (this.firstOptionSelectionMode === 'active') {
      const option = Array.from(this.list.querySelectorAll('[role="option"]:not([aria-disabled="true"])')).find(visible)
      option?.setAttribute('data-combobox-option-default', 'true')
    } else if (this.firstOptionSelectionMode === 'selected') {
      this.navigate(1)
    }
  }

  navigate(indexDiff = 1) {
    const focusEl = Array.from(this.list.querySelectorAll('[aria-selected="true"]')).find(visible)
    const els = Array.from(this.list.querySelectorAll('[role="option"]')).filter(visible)
    const focusIndex = els.indexOf(focusEl as HTMLElement)

    let indexOfItem = indexDiff === 1 ? 0 : els.length - 1
    if (focusEl && focusIndex >= 0) {
      const newIndex = focusIndex + indexDiff
      if (newIndex >= 0 && newIndex < els.length) indexOfItem = newIndex
    }

    const target = els[indexOfItem]
    if (!target) return

    for (const el of els) {
      el.removeAttribute('data-combobox-option-default')
      if (target === el) {
        this.input.setAttribute('aria-activedescendant', target.id)
        target.setAttribute('aria-selected', 'true')
        fireSelectEvent(target)
        target.scrollIntoView(this.scrollIntoViewOptions)
      } else {
        el.removeAttribute('aria-selected')
      }
    }
  }

  clearSelection() {
    this.input.removeAttribute('aria-activedescendant')
    for (const el of this.list.querySelectorAll('[aria-selected="true"], [data-combobox-option-default="true"]')) {
      el.removeAttribute('aria-selected')
      el.removeAttribute('data-combobox-option-default')
    }
  }

  resetSelection() {
    this.clearSelection()
    this.indicateDefaultOption()
  }
}

function keyboardBindings(event: KeyboardEvent, combobox: Combobox) {
  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
  if (event.shiftKey || event.metaKey || event.altKey) return
  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
  if (!combobox.ctrlBindings && event.ctrlKey) return

  /*
   * Safari is known to fire the a unprintable keydown event of 229
   * after the `compositionend` event.
   * This is a workaround to prevent the keydown event from firing and causing
   * the input to be saved.
   *
   * Related: https://bugs.webkit.org/show_bug.cgi?id=165004
   * Related: https://www.stum.de/2016/06/24/handling-ime-events-in-javascript/
   */
  if (isMacOS() && event.keyCode === 229 && !combobox.isComposing) {
    return
  }
  if (combobox.isComposing) return

  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
  switch (event.key) {
    case 'Enter':
      if (commit(combobox.input, combobox.list)) {
        event.preventDefault()
      }
      break
    case 'Tab':
      if (combobox.tabInsertsSuggestions && commit(combobox.input, combobox.list)) {
        event.preventDefault()
      }
      break
    case 'Escape':
      combobox.clearSelection()
      break
    case 'ArrowDown':
      combobox.navigate(1)
      event.preventDefault()
      break
    case 'ArrowUp':
      combobox.navigate(-1)
      event.preventDefault()
      break
    case 'n':
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (combobox.ctrlBindings && event.ctrlKey) {
        combobox.navigate(1)
        event.preventDefault()
      }
      break
    case 'p':
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (combobox.ctrlBindings && event.ctrlKey) {
        combobox.navigate(-1)
        event.preventDefault()
      }
      break
    default:
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (event.ctrlKey) break
  }
}

function commitWithElement(event: Event) {
  const target = (event.target as Element).closest('[role="option"]')
  if (!target) return
  if (target.getAttribute('aria-disabled') === 'true') return
  fireCommitEvent(target, {event})
}

function commit(input: HTMLInputElement, list: HTMLElement) {
  const target = list.querySelector('[aria-selected="true"], [data-combobox-option-default="true"]')
  if (!target) return false
  if (target.getAttribute('aria-disabled') === 'true') return true
  ;(target as HTMLElement).click()
  return true
}

function fireCommitEvent(target: Element, detail: any) {
  target.dispatchEvent(new CustomEvent('combobox-commit', {bubbles: true, detail}))
}

function fireSelectEvent(target: Element) {
  target.dispatchEvent(new Event('combobox-select', {bubbles: true}))
}

function visible(el: Element): boolean {
  const htmlElement = el as HTMLElement
  return (
    !htmlElement.hidden &&
    !(htmlElement instanceof HTMLInputElement && htmlElement.type === 'hidden') &&
    (htmlElement.offsetWidth > 0 || htmlElement.offsetHeight > 0)
  )
}

function trackComposition(event: CompositionEvent, combobox: Combobox) {
  combobox.isComposing = event.type === 'compositionstart'
  const list = document.getElementById(combobox.input.getAttribute('aria-controls') || '')
  if (!list) return
}
