import {useCallback, useEffect, useState, type MutableRefObject} from 'react'
import type {IssueTimelineFrontPaginated$data} from '../components/__generated__/IssueTimelineFrontPaginated.graphql'
import type {HighlightedTimelineBackwardPaginated$data} from '../components/__generated__/HighlightedTimelineBackwardPaginated.graphql'
import {VALUES} from '../constants/values'

type UseScrollToHighlightedProps = {
  data: IssueTimelineFrontPaginated$data | HighlightedTimelineBackwardPaginated$data
  highlightRef: React.MutableRefObject<HTMLDivElement | null>
  highlightedEventId: string | undefined
  showHighlightedTimeline?: boolean | ''
  highlightedTimelineRef?: React.MutableRefObject<HTMLDivElement | null>
  beforeAndAfterHighlightedItemLoaded?: boolean
}

// Keep track of whether we've scrolled already, because we only ever want to scroll once.
let scrolledToLoading = false
let scrolledToHighlighted = false
let isHighlightedItemVisible = false

export const useNewScrollToHighlighted = (
  isHighlightLoaded: boolean,
  highlightedItemRef: MutableRefObject<HTMLDivElement | null>,
  highlightedEventId: string | undefined,
) => {
  const [lastScrolledItemId, setLastScrolledItemId] = useState<string | undefined>(undefined)
  const [hasScrolled, setHasScrolled] = useState(false)
  const [highlightedItemVisible, setHighlightedItemVisible] = useState(false)
  const scrollToHighlightedEvent = useCallback(
    async (ref: MutableRefObject<HTMLDivElement | null>) => {
      if (!ref.current || highlightedItemVisible) return

      await mediaLoaded()

      ref.current?.scrollIntoView({behavior: 'instant', block: 'start', inline: 'start'})
      window.scrollBy({top: -VALUES.stickyHeaderHeight, behavior: 'instant'})
      setLastScrolledItemId(highlightedEventId)
      setHasScrolled(true)
    },
    [highlightedEventId, highlightedItemVisible],
  )

  // Observe, whether the highlighted item is visible.
  useEffect(() => {
    if (!highlightedItemRef?.current) return

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
  }, [highlightedItemRef])

  // If the highlighted item has been loaded, isn't visible in the viewport and it's different than the last that was scrolled to,
  // we reset the hasScrolled flag to allow scrolling again
  useEffect(() => {
    if (hasScrolled && isHighlightLoaded && !highlightedItemVisible) {
      if (lastScrolledItemId !== highlightedEventId) {
        setHasScrolled(false)
      }
    }
  }, [hasScrolled, highlightedEventId, highlightedItemVisible, isHighlightLoaded, lastScrolledItemId])

  // Scroll to the highlighted item if it's loaded.
  useEffect(() => {
    if (!isHighlightLoaded || !highlightedItemRef?.current || hasScrolled || highlightedItemVisible) return

    scrollToHighlightedEvent(highlightedItemRef)
  }, [hasScrolled, highlightedItemRef, isHighlightLoaded, highlightedItemVisible, scrollToHighlightedEvent])
}

export const useScrollToHighlighted = ({
  data,
  highlightRef,
  highlightedEventId,
  showHighlightedTimeline,
  highlightedTimelineRef,
  beforeAndAfterHighlightedItemLoaded,
}: UseScrollToHighlightedProps) => {
  const scrollToHighlightedEvent = useCallback(async () => {
    if (!data) return
    if (!highlightRef.current) return
    if (isHighlightedItemVisible) return
    if (scrolledToHighlighted) return
    if (beforeAndAfterHighlightedItemLoaded !== undefined && !beforeAndAfterHighlightedItemLoaded) return

    await mediaLoaded()

    highlightRef.current.scrollIntoView({behavior: 'instant'})
    window.scrollBy({top: -VALUES.stickyHeaderHeight, behavior: 'instant'})

    // eslint-disable-next-line react-compiler/react-compiler
    scrolledToHighlighted = true
  }, [beforeAndAfterHighlightedItemLoaded, data, highlightRef])

  // Observe, whether the highlighted item is visible.
  useEffect(() => {
    if (!highlightRef.current) return

    const observer = new IntersectionObserver(
      entries => {
        const entry = entries[0]
        if (!entry) return
        isHighlightedItemVisible = entry.isIntersecting
      },
      {rootMargin: `-${VALUES.stickyHeaderHeight}px 0px 0px 0px`, threshold: 1},
    )

    const header = highlightRef.current.children[0]
    if (!header) return

    observer.observe(header)

    return () => {
      observer.disconnect()
    }
  }, [highlightRef])

  // If the highlighted timeline is still loading, scroll to the loading indicator.
  useEffect(() => {
    if (
      showHighlightedTimeline === true &&
      !highlightRef.current &&
      !scrolledToLoading &&
      highlightedTimelineRef?.current
    ) {
      highlightedTimelineRef.current.scrollIntoView({behavior: 'instant'})
      scrolledToLoading = true
    }
  }, [showHighlightedTimeline, highlightRef, highlightedTimelineRef])

  // Scroll to the highlighted item if it's loaded.
  useEffect(() => {
    scrollToHighlightedEvent()
  }, [scrollToHighlightedEvent, highlightedEventId])
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
