import {AnimatePresence, motion} from 'motion/react'
import React, {useEffect, useMemo, useState} from 'react'
import {clsx} from 'clsx'
import styles from './AnimatedList.module.css'

/**
 * The visual transformation is calculated from the “card index”:
 *
 * • `cardIndex` = 0 → item is at the front of the stack (largest & most opaque).
 * • `cardIndex` = 1 → item is farther back (smaller & more transparent).
 * • `cardIndex` = 2 → item is at the back of the stack (smallest & most transparent).
 */
export function AnimatedListItem({children, indexFromEnd}: {children: React.ReactNode; indexFromEnd: number}) {
  const scale = 1 - 0.15 * indexFromEnd
  const opacity = 1 - 0.2 * indexFromEnd
  const offset = 10 - 10 * indexFromEnd
  return (
    <motion.div
      layout
      initial={{opacity: 0.5, scale: 1.05, top: 20, filter: 'blur(1px)'}}
      animate={{opacity, scale, top: offset, filter: 'blur(0px)'}}
      exit={{opacity: 0, scale: 0.5, top: -20, filter: 'blur(1px)'}}
      transition={{type: 'spring', stiffness: 280, damping: 60}}
      className={styles.animatedListItem}
    >
      {children}
    </motion.div>
  )
}

export interface AnimatedListProps {
  children: React.ReactNode
  delay?: number
  maxVisible?: number
  className?: string
}

/**
 * Each time the timer elapses, the current child at `pointer` is appended
 * to `visibleItems`. When the number of visible items exceeds `maxVisible`
 * the oldest item (the first in the array) is removed, creating the
 * animation of items “scrolling up” or “fading out”.
 *
 * The logic is driven by two pieces of state:
 * • `visibleItems` – the list currently rendered by `AnimatePresence`.
 * • `pointer`       – an index used to walk through `childrenArray`
 *   cyclically (`(prev + 1) % childrenArray.length`).
 */
export const AnimatedList = React.memo(
  ({children, className, delay = 3000, maxVisible = 2, ...props}: AnimatedListProps) => {
    const childrenArray = useMemo(() => {
      const base = Array.isArray(children) ? children : [children]
      return base
    }, [children])

    const [visibleItems, setVisibleItems] = useState<React.ReactNode[]>([])
    const [pointer, setPointer] = useState(0)

    useEffect(() => {
      // Show the very first card quickly (0-300 ms), regardless of the regular delay
      const currentDelay = visibleItems.length === 0 ? Math.min(delay, 300) : delay

      const timeout = setTimeout(() => {
        setVisibleItems(prev => {
          const next = [...prev, childrenArray[pointer]]
          if (next.length > maxVisible) next.shift()
          return next
        })
        setPointer(prev => (prev + 1) % childrenArray.length)
      }, currentDelay)

      return () => clearTimeout(timeout)
    }, [visibleItems, pointer, childrenArray, delay, maxVisible])

    return (
      <div className={clsx(styles.animatedListContainer, className)} {...props}>
        <AnimatePresence>
          {visibleItems.map((item, idx) => (
            <AnimatedListItem
              key={(item as React.ReactElement).key ?? `${idx}-${pointer}`}
              indexFromEnd={visibleItems.length - 1 - idx}
            >
              {item}
            </AnimatedListItem>
          ))}
        </AnimatePresence>
      </div>
    )
  },
)
AnimatedList.displayName = 'AnimatedList'
