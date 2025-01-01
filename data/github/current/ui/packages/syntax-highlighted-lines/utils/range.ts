export function createRange(element: HTMLDivElement, start: number, end: number) {
  if (!element.firstChild) return null
  if (!element.firstChild.textContent) return null
  if (start > element.firstChild.textContent.length) return null
  if (end > element.firstChild.textContent.length) return null

  const range = document.createRange()
  range.setStart(element.firstChild, start)
  range.setEnd(element.firstChild, end)

  return range
}
