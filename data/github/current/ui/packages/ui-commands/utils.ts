/** Return a copy of the array without the first encountered instance of `value` (based on `===` comparison). */
export function filterOnce<T>(array: readonly T[], value: T) {
  let encounteredOnce = false
  return array.filter(el => {
    if (el === value && !encounteredOnce) {
      encounteredOnce = true
      return false
    }
    return true
  })
}

export function getActiveModal() {
  const modals =
    // unfortunately, jsdom doesn't support yet the `:modal` pseudo-class
    // and throws an error in tests, so we remove it from the query
    process.env.NODE_ENV === 'test'
      ? [...document.querySelectorAll('[role="dialog"][aria-modal="true"]')]
      : [...document.querySelectorAll('dialog:modal, [role="dialog"][aria-modal="true"]')]
  const nonEmptyModals = modals.filter(modal => {
    return modal.childNodes.length > 0 && elementHasNonZeroHeight(modal)
  })
  return nonEmptyModals.length ? nonEmptyModals[nonEmptyModals.length - 1] : null
}

export function isInsideModal(modal: Element, element?: HTMLElement | null) {
  if (!element) {
    return false
  }

  return modal.contains(element) ?? false
}

function elementHasNonZeroHeight(element: Element): boolean {
  if (element.clientHeight > 0) return true

  for (const child of element.children) {
    if (elementHasNonZeroHeight(child)) return true
  }

  return false
}

export function setsEqual(a: Set<unknown>, b: Set<unknown>) {
  if (a.size !== b.size) return false
  for (const el of a) if (!b.has(el)) return false
  return true
}
