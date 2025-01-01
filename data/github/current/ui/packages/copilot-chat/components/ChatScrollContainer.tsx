import {clsx} from 'clsx'
import {createContext, type HTMLAttributes, useCallback, useContext, useEffect, useMemo, useRef, useState} from 'react'

import styles from './ChatScrollContainer.module.css'

interface ChatScrollContext {
  isScrolledUp: boolean
  scrollToBottom: (behavior: ScrollBehavior) => void
  scrollContainerHeight: string | undefined
}

const ChatScrollContext = createContext<ChatScrollContext | null>(null)

/**
 * Functional container that handles auto-scroll on load and when new messages arrive. Provides context for
 * `useChatScroll`.
 */
export function ChatScrollContainer({
  children,
  disabled,
  ...props
}: {disabled?: boolean} & HTMLAttributes<HTMLDivElement>) {
  const containerRef = useRef<HTMLDivElement>(null)
  const endRef = useRef<HTMLDivElement>(null)

  // Observe if scrolled to end
  const [isScrolledUp, setIsScrolledUp] = useState(false)
  useEffect(() => {
    const scrollObserver = new IntersectionObserver(([entry]) => setIsScrolledUp(!entry?.isIntersecting), {
      root: containerRef.current!,
      threshold: 0,
      // The margin means the user must be scrolled up more than 50px to be considered 'scrolled up'
      rootMargin: '50px',
    })

    scrollObserver.observe(endRef.current!)
    return () => scrollObserver.disconnect()
  }, [])

  // Track the inside height of the container (CSS `height` value string)
  const [scrollContainerHeight, setScrollContainerHeight] = useState<string>()
  useEffect(() => {
    const handleResize = () => {
      if (!containerRef.current) return
      const computedStyles = getComputedStyle(containerRef.current)
      // using calc allows us to avoid parsing the values since it all stays in CSS
      const innerHeight = `calc(${containerRef.current.clientHeight}px - ${computedStyles.paddingTop} - ${computedStyles.paddingBottom})`
      setScrollContainerHeight(innerHeight)
    }
    const resizeObserver = new ResizeObserver(handleResize)

    handleResize()
    resizeObserver.observe(containerRef.current!)
    return () => resizeObserver.disconnect()
  }, [])

  const scrollToBottom = useCallback(
    (behavior: ScrollBehavior) => {
      if (disabled) return

      endRef.current?.scrollIntoView({behavior, block: 'end'})
    },
    [disabled],
  )

  const contextValue = useMemo(
    () => ({isScrolledUp, scrollToBottom, scrollContainerHeight}),
    [isScrolledUp, scrollToBottom, scrollContainerHeight],
  )

  return (
    <ChatScrollContext.Provider value={contextValue}>
      <div ref={containerRef} {...props} className={clsx(styles.container, props.className)}>
        {children}

        <div ref={endRef} style={{height: '1px', marginTop: '-1px'}} />
      </div>
    </ChatScrollContext.Provider>
  )
}

/** Get scroll state & controls for the chat scroll container. If used outside of a container, will be a noop. */
export const useChatScroll = () => {
  const context = useContext(ChatScrollContext)
  if (!context) throw new Error('useChatScroll may only be called in a descendant of ChatScrollContainer')
  return context
}
