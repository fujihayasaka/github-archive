export const makeTablesTabbable = (table: Element) => {
  if (table.scrollWidth > table.clientWidth) {
    if (table.getAttribute('tabindex') === null) {
      table.setAttribute('tabindex', '0')
    }
  } else {
    table.removeAttribute('tabindex')
  }
}
