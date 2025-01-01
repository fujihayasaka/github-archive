// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {useEffect, useRef, useState} from 'react'

const getItemIndex = (element: Element) => {
  const index = element.getAttribute('data-index')
  if (index) {
    return parseInt(index)
  }
  return -1
}

interface ActiveItemDetectionRef {
  itemContainerRef: React.MutableRefObject<HTMLElement | null>
  threshold?: number
}

const useActiveItemDetection = ({itemContainerRef, threshold = 0}: ActiveItemDetectionRef) => {
  const [currentItemIndex, setCurrentItemIndex] = useState<number>(0)
  const [previousItemIndex, setPreviousItemIndex] = useState<number>(-1)
  const currentItemIndexRef = useRef<number>(currentItemIndex)

  useEffect(() => {
    if (!itemContainerRef.current) return

    // Track the scroll direction
    let lastScrollTop = 0
    let scrollDirection: 'up' | 'down' = 'down'
    const trackScrollDirection = () => {
      const currentScrollTop = window.scrollY

      if (currentScrollTop > lastScrollTop) {
        scrollDirection = 'down'
      } else if (currentScrollTop < lastScrollTop) {
        scrollDirection = 'up'
      }

      lastScrollTop = currentScrollTop
    }

    // eslint-disable-next-line github/prefer-observers
    document.scrollingElement?.addEventListener('scroll', trackScrollDirection)

    // Track the current item
    const visibilityStates: IntersectionObserverEntry[] = []

    const pageSectionObserver = new IntersectionObserver(
      entries => {
        // Update all entries in the visibilityStates array
        for (const entry of entries) {
          const index = getItemIndex(entry.target)
          visibilityStates[index] = entry
        }

        // Find the most visible item
        const sorted = visibilityStates
          .slice(0)
          .sort((a, b) => a.intersectionRatio - b.intersectionRatio)
          .sort((a, b) =>
            scrollDirection === 'down'
              ? getItemIndex(b.target) - getItemIndex(a.target)
              : getItemIndex(a.target) - getItemIndex(b.target),
          )
        const activeItem = sorted.find(v => v.isIntersecting)

        const activeItemIndex = activeItem ? getItemIndex(activeItem.target) : -1
        const intersectionRatio = activeItem ? parseFloat(activeItem.intersectionRatio.toFixed(3)) : 0

        if (
          activeItem &&
          (!currentItemIndexRef.current || intersectionRatio >= threshold) &&
          currentItemIndexRef.current !== activeItemIndex
        ) {
          setCurrentItemIndex(activeItemIndex)
        }
      },
      {threshold},
    )

    for (let i = 0; i < itemContainerRef.current.children.length; i++) {
      const section = itemContainerRef.current.children[i] as HTMLElement
      if (section) {
        section.setAttribute('data-index', i.toString())
        pageSectionObserver.observe(section)
      }
    }

    return () => {
      document.scrollingElement?.removeEventListener('scroll', trackScrollDirection)
      pageSectionObserver.disconnect()
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    setPreviousItemIndex(currentItemIndexRef.current)
    currentItemIndexRef.current = currentItemIndex
  }, [currentItemIndex])

  return {
    currentItemIndex,
    previousItemIndex,
  }
}

export default useActiveItemDetection
