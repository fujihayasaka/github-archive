export function toggleVisibility(selector: string, show: boolean): void {
  const element = document.querySelector(selector) as HTMLElement
  if (element) element.hidden = !show
}

export function toggleContainerVisibility(selector: string, containerSelector: string, show: boolean): void {
  const element = document.querySelector(selector) as HTMLElement
  if (!element) return

  const container = element.closest<HTMLElement>(containerSelector)
  if (container) container.hidden = !show
}
