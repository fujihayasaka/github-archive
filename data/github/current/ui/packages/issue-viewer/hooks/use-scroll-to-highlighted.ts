import {useCallback, useEffect, useState, type MutableRefObject} from 'react'
import {VALUES} from '../constants/values'
import {isFeatureEnabled} from '@github-ui/feature-flags'

export const useNewScrollToHighlighted = (
  isHighlightLoaded: boolean,
  highlightedItemRef: MutableRefObject<HTMLDivElement | null>,
  highlightedEventId: string | undefined,
  highlightedReadyToScroll: boolean,
) => {
  const [lastScrolledItemId, setLastScrolledItemId] = useState<string | undefined>(undefined)
  const [hasScrolled, setHasScrolled] = useState(false)
  const [highlightedItemVisible, setHighlightedItemVisible] = useState(false)

  const [notificationShelfHeight, setNotificationShelfHeight] = useState(0)
  const notificationShelf = document.getElementById('notification-shelf')

  const isObserverDisabled = isFeatureEnabled('issues_react_disable_sticky_header_observer')

  const scrollToHighlightedEvent = useCallback(
    async (ref: MutableRefObject<HTMLDivElement | null>) => {
      if (!ref.current || highlightedItemVisible || !highlightedReadyToScroll) return

      await mediaLoaded()

      ref.current?.scrollIntoView({behavior: 'instant', block: 'start', inline: 'start'})
      window.scrollBy({top: -(VALUES.stickyHeaderHeight + notificationShelfHeight), behavior: 'instant'})
      setLastScrolledItemId(highlightedEventId)
      setHasScrolled(true)
    },
    [highlightedEventId, highlightedItemVisible, highlightedReadyToScroll, notificationShelfHeight],
  )

  // Observe, whether the highlighted item is visible.
  useEffect(() => {
    if (!highlightedItemRef?.current || isObserverDisabled) return

    const observer = new IntersectionObserver(
      entries => {
        const entry = entries[0]
        if (!entry) return
        setHighlightedItemVisible(entry.isIntersecting)
      },
      {rootMargin: `-${VALUES.stickyHeaderHeight}px 0px 0px 0px`, threshold: 1},
    )

    const header = highlightedItemRef.current.children[0]
    if (!header) return

    observer.observe(header)

    return () => {
      observer.disconnect()
    }
  }, [highlightedItemRef, isObserverDisabled])

  // If the highlighted item has been loaded, isn't visible in the viewport and it's different than the last that was scrolled to,
  // we reset the hasScrolled flag to allow scrolling again
  useEffect(() => {
    if (hasScrolled && isHighlightLoaded && !highlightedItemVisible) {
      if (lastScrolledItemId !== highlightedEventId) {
        setHasScrolled(false)
      }
    }
  }, [hasScrolled, highlightedEventId, highlightedItemVisible, isHighlightLoaded, lastScrolledItemId])

  // If the notification shelf is visible, we need to set the height to scroll correctly and
  // we reset the hasScrolled flag to allow scrolling again
  useEffect(() => {
    if (notificationShelf && !notificationShelfHeight) {
      setHasScrolled(false)
      setNotificationShelfHeight(notificationShelf?.getBoundingClientRect().height || 0)
    }
  }, [notificationShelf, hasScrolled])

  // Scroll to the highlighted item if it's loaded.
  useEffect(() => {
    if (!isHighlightLoaded || !highlightedItemRef?.current || hasScrolled || highlightedItemVisible) return

    scrollToHighlightedEvent(highlightedItemRef)
  }, [hasScrolled, highlightedItemRef, isHighlightLoaded, highlightedItemVisible, scrollToHighlightedEvent])
}

// Copied from: app/assets/modules/github/behaviors/timeline/progressive.ts.
// resolves when comment body videos have loaded enough data to render the preview image
async function videosReady(): Promise<unknown> {
  const videos: NodeListOf<HTMLVideoElement> = document.querySelectorAll(VALUES.commentVideo)
  const videoLoads = Array.from(videos).map(v => {
    return new Promise<HTMLVideoElement>(resolve => {
      if (v.readyState >= v.HAVE_METADATA) {
        resolve(v)
      } else {
        // don't wait forever :)
        const timeout = setTimeout(() => resolve(v), VALUES.scrollWaitMediaTimeout)
        const done = () => {
          clearTimeout(timeout)
          resolve(v)
        }
        v.addEventListener('loadeddata', () => {
          if (v.readyState >= v.HAVE_METADATA) done()
        })
        v.addEventListener('error', () => done())
      }
    })
  })
  return Promise.all(videoLoads)
}

// Copied from: app/assets/modules/github/behaviors/timeline/progressive.ts.
// resolves when comment body images are loaded
async function imagesReady(): Promise<unknown> {
  const images: NodeListOf<HTMLImageElement> = document.querySelectorAll(VALUES.commentImage)
  const imageLoads = Array.from(images).map(i => {
    new Promise<HTMLImageElement>(resolve => {
      if (i.complete) {
        resolve(i)
      } else {
        const timeout = setTimeout(() => resolve(i), VALUES.scrollWaitMediaTimeout)
        const done = () => {
          clearTimeout(timeout)
          resolve(i)
        }
        i.addEventListener('load', () => done())
        i.addEventListener('error', () => done())
      }
    })
  })
  return Promise.all(imageLoads)
}

// Copied from: app/assets/modules/github/behaviors/timeline/progressive.ts.
async function mediaLoaded(): Promise<unknown> {
  return Promise.all([videosReady(), imagesReady()])
}
