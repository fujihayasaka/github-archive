import {type RefObject, useEffect, useState} from 'react'

export function useIsScrolledToEnd(scrollContainerRef: RefObject<HTMLElement | null>) {
  const [scrolledToEnd, setScrolledToEnd] = useState(false)
  useEffect(() => {
    const root = scrollContainerRef.current
    const lastChild = root?.lastElementChild
    if (!lastChild) return

    const observer = new IntersectionObserver(([entry]) => setScrolledToEnd(entry?.isIntersecting ?? true), {
      root,
      threshold: 1,
    })

    observer.observe(lastChild)
    return () => observer.disconnect()
  })

  return scrolledToEnd
}
