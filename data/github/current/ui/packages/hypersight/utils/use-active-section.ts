import {useState, useEffect} from 'react'

export function useActiveSection(headingIds: string[]) {
  const [activeId, setActiveId] = useState<string | null>(null)

  useEffect(() => {
    if (headingIds.length === 0) return

    // Get all heading elements
    const headingElements = headingIds
      .map(id => document.getElementById(id))
      .filter((el): el is HTMLElement => el !== null)

    // If no heading elements are found yet, return early
    if (headingElements.length === 0) return

    // Helper to find which heading is currently in view
    const getActiveHeading = () => {
      // Get all headings that are in view
      const visibleHeadings = headingElements.filter(el => {
        const rect = el.getBoundingClientRect()
        // Consider a heading "visible" if it's within the viewport
        return rect.top >= 0 && rect.top <= window.innerHeight * 0.5
      })

      // If no headings are visible, check if we're at the bottom of the page
      if (visibleHeadings.length === 0) {
        const isAtBottom = window.innerHeight + window.pageYOffset >= document.documentElement.scrollHeight - 100

        // Get the first heading's position
        const firstHeadingTop = headingElements[0]?.offsetTop ?? 0

        if (isAtBottom && headingElements.length > 0) {
          // Return the last heading if we're at the bottom
          return headingElements[headingElements.length - 1]
        }

        // If we're scrolled above all headings, return the first one
        if (window.pageYOffset <= firstHeadingTop) {
          return headingElements[0]
        }

        // Find the closest heading above our current position
        return headingElements.reduce((prev, curr) => {
          if (!prev || !curr) return prev || curr
          const currDist = Math.abs((curr.offsetTop || 0) - window.pageYOffset)
          const prevDist = Math.abs((prev.offsetTop || 0) - window.pageYOffset)
          return currDist < prevDist ? curr : prev
        })
      }

      // Return the first visible heading
      return visibleHeadings[0]
    }

    // Update active heading
    const updateActiveHeading = () => {
      const activeHeading = getActiveHeading()
      if (activeHeading && activeHeading.id !== activeId) {
        setActiveId(activeHeading.id)
      }
    }

    // Set up intersection observer for initial detection
    const observer = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            updateActiveHeading()
          }
        }
      },
      {
        rootMargin: '-10% 0px -70% 0px',
        threshold: [0, 1],
      },
    )

    // Observe all headings
    for (const el of headingElements) {
      observer.observe(el)
    }

    // Add scroll listener for more precise updates
    // eslint-disable-next-line github/prefer-observers
    window.addEventListener('scroll', updateActiveHeading)

    // Initial check
    updateActiveHeading()

    return () => {
      for (const el of headingElements) {
        observer.unobserve(el)
      }
      window.removeEventListener('scroll', updateActiveHeading)
    }
  }, [headingIds, activeId])

  return activeId
}
