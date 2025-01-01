// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {useCallback, useEffect, useRef} from 'react'

import {validExtensions, type Extension} from './HeroUI.types'
import {wait} from '../../../../utils/time'

interface MotionRef {
  wrapperRef: React.RefObject<HTMLDivElement>
  extensionMenuRef: React.RefObject<HTMLUListElement>
  setIsExtensionMenuOpen: (value: boolean) => void
  onExtensionClick: (extension: Extension, isFromUser?: boolean) => void
  isAnimationPausedRef: React.RefObject<boolean>
  isManualModeRef: React.RefObject<boolean>
}

const useMotion = ({
  wrapperRef,
  extensionMenuRef,
  setIsExtensionMenuOpen,
  onExtensionClick,
  isAnimationPausedRef,
  isManualModeRef,
}: MotionRef) => {
  const timeoutRefs = useRef<NodeJS.Timeout[]>([])
  const previousIndexRef = useRef<number>(-1)
  const isFirstRun = useRef<boolean>(true)
  const isAnimationRunningRef = useRef(false)

  const showExtensionMenu = useCallback(async () => {
    if (isAnimationRunningRef.current) return
    if (![wrapperRef.current, extensionMenuRef.current].every(Boolean)) return

    try {
      isAnimationRunningRef.current = true

      // Wait 2s on first run
      if (isFirstRun.current) {
        isFirstRun.current = false
        timeoutRefs.current.push(await wait(1000))
      }

      setIsExtensionMenuOpen(true)

      // Get unique random hovered item
      let hoveredItemsCount = Math.ceil(Math.random() * validExtensions.length)
      if (hoveredItemsCount === previousIndexRef.current) {
        hoveredItemsCount++
        if (hoveredItemsCount > validExtensions.length) {
          hoveredItemsCount = 1
        }
      }
      previousIndexRef.current = hoveredItemsCount

      // Hover over each extension item
      const extensionItems = Array.from(extensionMenuRef.current?.children as HTMLCollection) as HTMLLIElement[]
      const hoveredItems = extensionItems.slice(0, hoveredItemsCount)
      const selectedItemIndex = hoveredItems.length - 1

      if (!isAnimationPausedRef.current) {
        for (const extensionItem of hoveredItems) {
          if (!isAnimationPausedRef.current) timeoutRefs.current.push(await wait(500))
          for (const item of hoveredItems) {
            item.classList.remove('isSelected')
          }
          extensionItem.classList.add('isSelected')
        }
      }

      if (!isAnimationPausedRef.current) timeoutRefs.current.push(await wait(500))

      // Select next extension item
      if (isManualModeRef.current) {
        for (const item of extensionItems) {
          item.classList.remove('isSelected')
        }
      } else {
        onExtensionClick(validExtensions[selectedItemIndex] as Extension, false)
        ;(hoveredItems[selectedItemIndex] as HTMLLIElement).classList.remove('isSelected')
      }

      if (!isAnimationPausedRef.current) timeoutRefs.current.push(await wait(3000))
    } finally {
      isAnimationRunningRef.current = false

      if (!isAnimationPausedRef.current) {
        showExtensionMenu() // Restart animation
      }
    }
  }, [extensionMenuRef, isAnimationPausedRef, isManualModeRef, onExtensionClick, setIsExtensionMenuOpen, wrapperRef])

  useEffect(() => {
    return () => {
      if (timeoutRefs.current) {
        // eslint-disable-next-line react-hooks/react-compiler
        // eslint-disable-next-line react-hooks/exhaustive-deps
        for (const timeoutRef of timeoutRefs.current) {
          clearTimeout(timeoutRef)
        }
      }
    }
  }, [])

  return {
    showExtensionMenu,
  }
}

export default useMotion
