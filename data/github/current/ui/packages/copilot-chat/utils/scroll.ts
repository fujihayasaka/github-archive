function easeInOutQuad(t: number) {
  if (t < 0.5) {
    return 2 * t * t // handles ease-in
  } else {
    return -1 + (4 - 2 * t) * t // handles ease-out
  }
}

export function smoothScrollTo(element: HTMLElement, target: number, duration: number) {
  const start = element.scrollTop
  const change = target - start
  const startTime = performance.now()

  const animateScroll = (currentTime: number) => {
    const elapsedTime = currentTime - startTime
    const progress = Math.min(elapsedTime / duration, 1)
    const easedProgress = easeInOutQuad(progress)
    element.scrollTop = start + change * easedProgress

    if (progress < 1) {
      requestAnimationFrame(animateScroll)
    }
  }

  requestAnimationFrame(animateScroll)
}

export function isScrollable(element: HTMLElement): boolean {
  if (!element.scrollTo) return false // This happens in the jest tests on CI

  return window.getComputedStyle(element).overflowY === 'auto'
}

export function scrollToBottomWithDelay(container: HTMLElement | null, delay: number) {
  setTimeout(() => {
    smoothScrollTo(container || document.body, (container || document.body).scrollHeight, 1000)
  }, delay)
}
