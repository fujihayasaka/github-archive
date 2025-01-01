export function toggleVisibility(selector: string, show: boolean): void {
  const element = document.querySelector(selector) as HTMLElement
  if (element) element.hidden = !show
}

export function toggleButtonEnabled(selector: string, enabled: boolean): void {
  const element = document.querySelector(selector) as HTMLButtonElement
  if (element) element.disabled = !enabled
}

export function toggleContainerVisibility(selector: string, containerSelector: string, show: boolean): void {
  const element = document.querySelector(selector) as HTMLElement
  if (!element) return

  const container = element.closest<HTMLElement>(containerSelector)
  if (container) container.hidden = !show
}
