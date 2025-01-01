// A wrapper component to refresh the video when the user hovers over it

import type {SafeHTMLString} from '@github-ui/safe-html'
import {useCallback, useEffect, useState} from 'react'
import {fetchQuery, useRelayEnvironment} from 'react-relay'
import type {GraphQLTaggedNode, OperationType} from 'relay-runtime'

type RefreshVideoWrapperProps<T extends OperationType> = {
  id: string
  bodyHTML: SafeHTMLString
  query: GraphQLTaggedNode
  bodyRef: React.RefObject<HTMLDivElement>
  getHTML: (fetchResult: Awaited<T['response']> | undefined) => string | undefined
  children: React.ReactNode
}

// this is needed because the video URL expires after 5 minutes
export function RefreshVideoWrapper<T extends OperationType>({
  id,
  bodyHTML,
  query,
  bodyRef,
  getHTML,
  children,
}: RefreshVideoWrapperProps<T>) {
  const REFRESH_TIMEOUT = 4 * 60 * 1000 // 4 minutes
  const MOUSEOVER_DEBOUNCE = 10000 // 10 seconds
  const [lastFetch, setLastFetch] = useState(() => new Date())
  const environment = useRelayEnvironment()

  // Handles refetching and setting the video / image src after the REFRESH_TIMEOUT has been met
  const mouseoverHandler = useCallback(async () => {
    // Check if we have an image / video and the FF is enabled
    const IMAGE_VIDEO_TAG_REGEX = /<(?:video|img)/i
    if (!IMAGE_VIDEO_TAG_REGEX.test(bodyHTML)) return
    const now = new Date()

    // Check the timeout
    if (Math.abs(now.getTime() - lastFetch.getTime()) < REFRESH_TIMEOUT) return

    const result = await fetchQuery<T>(environment, query, {
      id,
    }).toPromise()
    const fetchedHtml = getHTML(result)

    // Replace any video or image elements in the ref
    if (fetchedHtml) {
      const parser = new DOMParser()
      const currentDoc = bodyRef.current
      const fetchedDoc = parser.parseFromString(fetchedHtml, 'text/html')
      if (!currentDoc || !fetchedDoc) return

      const updateSrcAttributes = (tagName: string) => {
        const currentElements = currentDoc.getElementsByTagName(tagName)
        const fetchedElements = fetchedDoc.getElementsByTagName(tagName)

        for (let i = 0; i < currentElements.length; i++) {
          if (fetchedElements[i]) {
            ;(currentElements[i] as HTMLImageElement | HTMLVideoElement).src = (
              fetchedElements[i] as HTMLImageElement | HTMLVideoElement
            ).src
          }
        }
      }

      updateSrcAttributes('img')
      updateSrcAttributes('video')
      // Ensure the last fetch is updated
      setLastFetch(now)
    }
  }, [bodyHTML, lastFetch, REFRESH_TIMEOUT, environment, query, id, getHTML, bodyRef])

  //TODO: Maybe we can use `use-debounce` here
  useEffect(() => {
    const element = bodyRef?.current?.parentElement
    if (!element) return

    // Custom debounce logic as we can't leverage useDebounce
    // In this useEffect hook (that relies on the issueBodyRef to attach the mouseover event)
    let lastCallTime: number | null = null
    let isFirstCall = true

    const debouncedMouseoverHandler = () => {
      const now = Date.now()

      if (isFirstCall) {
        mouseoverHandler()
        isFirstCall = false
        lastCallTime = now
      } else if (lastCallTime === null || now - lastCallTime > MOUSEOVER_DEBOUNCE) {
        mouseoverHandler()
        lastCallTime = now
      }
    }

    // Add / tear down the event listener
    element.addEventListener('mouseover', debouncedMouseoverHandler)

    return () => {
      element.removeEventListener('mouseover', debouncedMouseoverHandler)
    }
  }, [mouseoverHandler, bodyRef])

  return <>{children}</>
}
