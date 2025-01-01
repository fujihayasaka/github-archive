import {useCallback, useEffect, useRef} from 'react'

import {validExtensions, type Extension} from './CopilotExtensionsHeroUI.types'
import {wait} from '../utils/time'

interface MotionRef {
  wrapperRef: React.RefObject<HTMLDivElement>
  extensionMenuRef: React.RefObject<HTMLUListElement>
  setIsExtensionMenuOpen: (value: boolean) => void
  onExtensionClick: (extension: Extension, isFromUser?: boolean) => void
}

const useMotion = ({wrapperRef, extensionMenuRef, setIsExtensionMenuOpen, onExtensionClick}: MotionRef) => {
  const timeoutRefs = useRef<NodeJS.Timeout[]>([])

  const showExtensionMenu = useCallback(async () => {
    if (![wrapperRef.current, extensionMenuRef.current].every(Boolean)) return

    // Double check because the linter doesn't understand it's already checked above...
    if (wrapperRef.current) wrapperRef.current.style.pointerEvents = 'none'

    timeoutRefs.current.push(await wait(1000))
    setIsExtensionMenuOpen(true)

    const extensionItems = Array.from(extensionMenuRef.current?.children as HTMLCollection) as HTMLLIElement[]
    const hoveredItemsCount = Math.ceil(Math.random() * validExtensions.length)
    const hoveredItems = extensionItems.slice(0, hoveredItemsCount)
    const selectedItemIndex = hoveredItems.length - 1

    for (const extensionItem of hoveredItems) {
      timeoutRefs.current.push(await wait(500))
      for (const item of hoveredItems) {
        item.classList.remove('isSelected')
      }
      extensionItem.classList.add('isSelected')
    }

    onExtensionClick(validExtensions[selectedItemIndex] as Extension, false)
    ;(hoveredItems[selectedItemIndex] as HTMLLIElement).classList.remove('isSelected')

    timeoutRefs.current.push(await wait(1000))
    // Double check because the linter doesn't understand it's already checked above...
    if (wrapperRef.current) wrapperRef.current.style.pointerEvents = ''
  }, [extensionMenuRef, onExtensionClick, setIsExtensionMenuOpen, wrapperRef])

  useEffect(() => {
    return () => {
      if (timeoutRefs.current) {
        // eslint-disable-next-line react-compiler/react-compiler
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
