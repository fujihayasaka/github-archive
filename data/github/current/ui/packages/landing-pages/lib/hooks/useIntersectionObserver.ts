// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {useEffect, useRef, useState} from 'react'

const useIntersectionObserver = (
  element: React.RefObject<Element>,
  options: Omit<IntersectionObserverInit, 'threshold'> & {
    isOnce?: boolean
    threshold?: number | {mobile?: number; desktop: number}
  } = {},
  shouldUseDesktopThreshold = true,
) => {
  const [isIntersecting, setIsIntersecting] = useState<boolean>(false)
  const observer = useRef<IntersectionObserver | null>(null)

  useEffect(() => {
    if (element?.current) {
      if (observer.current) {
        observer.current.unobserve(element.current)
        observer.current.disconnect()
      }

      observer.current = new IntersectionObserver(
        ([entry]) => {
          if (options.isOnce && entry?.isIntersecting) {
            observer.current?.disconnect()
          }

          setIsIntersecting(!!entry?.isIntersecting)
        },
        {
          ...options,
          threshold:
            typeof options.threshold === 'number'
              ? options.threshold
              : options.threshold?.[shouldUseDesktopThreshold ? 'desktop' : 'mobile'],
        },
      )

      observer.current.observe(element.current)
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [element, shouldUseDesktopThreshold])

  useEffect(() => {
    return () => {
      if (element?.current && observer.current) {
        // eslint-disable-next-line react-compiler/react-compiler
        // eslint-disable-next-line react-hooks/exhaustive-deps
        observer.current.unobserve(element.current)
      }
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return {
    isIntersecting,
    observer,
  }
}

export default useIntersectionObserver
