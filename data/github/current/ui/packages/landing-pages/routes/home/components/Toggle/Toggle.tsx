import {Text} from '@primer/react-brand'
import {useDebounce} from '@github-ui/use-debounce'
import {useCallback, useEffect, useRef, useState, type KeyboardEvent} from 'react'

import SvgBorder, {type Gradient} from '../SvgBorder/SvgBorder'
import {checkPrefersReducedMotion} from '../../../../lib/utils/platform'

interface ToggleItem {
  label: string
  value: string
}

interface ToggleProps {
  items: ToggleItem[]
  onToggle: (value: string) => void
  currentIndex: number
  hasBackground?: boolean
  ariaLabel?: string
}

const defaultProps: Partial<ToggleProps> = {
  hasBackground: false,
  ariaLabel: '',
}

const BORDER_RADIUS = 20 // px
const BORDER_GRADIENT: Gradient[] = [
  {color: '#fff', offset: 0},
  {color: '#bbb', offset: 100},
]

const SCROLL_THRESHOLD = 10 // px

const Toggle: React.FC<ToggleProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {items, onToggle, currentIndex, hasBackground, ariaLabel} = initializedProps

  const [isMounted, setMounted] = useState<boolean>(false)
  const [shouldReduceMotion, setShouldReduceMotion] = useState<boolean>(false)
  const currentIndexRef = useRef<number>(currentIndex)
  const wrapperRef = useRef<HTMLDivElement>(null)
  const contentRef = useRef<HTMLDivElement>(null)
  const selectionRef = useRef<SVGSVGElement>(null)
  const indicatorsRef = useRef<HTMLDivElement>(null)

  const updateSelection = useCallback(() => {
    if (!wrapperRef.current || !contentRef.current || !selectionRef.current) return

    const tabs: NodeListOf<HTMLButtonElement> = wrapperRef.current.querySelectorAll('[role="tab"]')
    const selectedTab = tabs[currentIndexRef.current]
    if (!selectedTab) return

    const selectionRect = selectionRef.current.querySelector('rect')
    if (!selectionRect) return

    selectionRef.current.style.width = `${contentRef.current.scrollWidth}px`

    // Force a reflow to ensure responsiveness
    selectionRect.style.display = 'none'
    // eslint-disable-next-line @typescript-eslint/no-unused-expressions
    selectionRect.clientHeight
    selectionRect.style.display = ''

    selectionRect.style.width = `${selectedTab.offsetWidth - 2}px`
    selectionRect.style.height = `${selectedTab.offsetHeight - 2}px`
    selectionRect.style.transform = `translate(${selectedTab.offsetLeft}px, ${selectedTab.offsetTop}px)`
  }, [])

  const updateScrollIndicators = useDebounce(
    () => {
      if (!contentRef.current || !indicatorsRef.current) return

      const {scrollLeft, scrollWidth, offsetWidth} = contentRef.current

      const scrollDelta = scrollWidth - offsetWidth
      const shouldShowIndicators = scrollDelta >= SCROLL_THRESHOLD

      if (shouldShowIndicators && Math.floor(scrollLeft) > 0)
        indicatorsRef.current.classList.add('Toggle-indicators--left')
      else indicatorsRef.current.classList.remove('Toggle-indicators--left')

      if (shouldShowIndicators && Math.ceil(scrollLeft) < scrollDelta)
        indicatorsRef.current.classList.add('Toggle-indicators--right')
      else indicatorsRef.current.classList.remove('Toggle-indicators--right')
    },
    200,
    {
      leading: true,
      trailing: true,
    },
  )

  const onClick = useCallback(
    (itemIndex: number) => {
      if (items[itemIndex]) {
        onToggle(items[itemIndex].value)
      }
    },
    [items, onToggle],
  )

  const onKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (!wrapperRef.current) return

      const tabs = Array.from(wrapperRef.current.querySelectorAll('[role="tab"]'))

      if (document.activeElement instanceof HTMLElement) {
        const currentTabIndex = tabs.indexOf(document.activeElement)
        let newTabIndex = currentTabIndex

        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        if (event.key === 'ArrowLeft') {
          // Move to the previous tab, wrapping around if necessary
          newTabIndex = currentTabIndex === 0 ? tabs.length - 1 : currentTabIndex - 1
          // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        } else if (event.key === 'ArrowRight') {
          // Move to the next tab, wrapping around if necessary
          newTabIndex = currentTabIndex === tabs.length - 1 ? 0 : currentTabIndex + 1
        }

        if (newTabIndex !== currentTabIndex && tabs[newTabIndex]) {
          // @ts-expect-error - TS doesn't know that it's always defined
          tabs[newTabIndex].focus()
          onClick(newTabIndex)
        }
      }
    },
    [onClick],
  )

  useEffect(() => {
    currentIndexRef.current = currentIndex

    updateSelection()
    updateScrollIndicators()

    // Ensure the selected item is visible even on both edges
    if (contentRef.current) {
      const scrollBehavior: ScrollBehavior = shouldReduceMotion ? 'instant' : 'smooth'

      if (currentIndex === 0) {
        contentRef.current.scrollTo({left: 0, behavior: scrollBehavior})
      } else if (currentIndex === items.length - 1) {
        contentRef.current.scrollTo({left: contentRef.current.scrollWidth, behavior: scrollBehavior})
      }
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentIndex])

  useEffect(() => {
    if (!isMounted || !contentRef.current) return
    setShouldReduceMotion(checkPrefersReducedMotion())

    // eslint-disable-next-line github/prefer-observers
    window.addEventListener('resize', updateSelection)
    // eslint-disable-next-line github/prefer-observers
    contentRef.current.addEventListener('scroll', updateScrollIndicators)

    updateSelection()
    updateScrollIndicators()
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isMounted])

  useEffect(() => {
    setMounted(true)

    return () => {
      updateScrollIndicators.cancel()

      window.removeEventListener('resize', updateSelection)
      // eslint-disable-next-line react-compiler/react-compiler
      // eslint-disable-next-line react-hooks/exhaustive-deps
      if (contentRef.current) contentRef.current.removeEventListener('scroll', updateScrollIndicators)
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div ref={wrapperRef} className="Toggle-wrapper" role="tablist" aria-label={ariaLabel}>
      <div className={`Toggle-container ${hasBackground ? 'Toggle-container--background' : ''}`}>
        <div ref={contentRef} className="Toggle">
          <SvgBorder
            ref={selectionRef}
            gradient={BORDER_GRADIENT}
            borderRadius={BORDER_RADIUS}
            className="Toggle-selection"
          />

          {items.map((item, index) => (
            <button
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={`item_${index}`}
              role="tab"
              className={`Toggle-button ${currentIndex === index ? 'Toggle-button--selected' : ''}`}
              onClick={() => onClick(index)}
              onKeyDown={onKeyDown}
            >
              <Text weight="medium">{item.label}</Text>
            </button>
          ))}
        </div>

        <div ref={indicatorsRef} className="Toggle-indicators" />
      </div>
    </div>
  )
}

export default Toggle
