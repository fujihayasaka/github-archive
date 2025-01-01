import {Text, ActionMenu} from '@primer/react-brand'
import {useCallback, useEffect, useRef, useState, type KeyboardEvent} from 'react'

import SvgBorder, {type Gradient} from '../SvgBorder/SvgBorder'

interface ToggleItem {
  label: string
  value: string
}

interface ToggleProps {
  items: ToggleItem[]
  onToggle: (value: string) => void
  currentIndex: number
  hasBackground?: boolean
  ariaControls?: string
}

const defaultProps: Partial<ToggleProps> = {
  hasBackground: false,
  ariaControls: '',
}

const BORDER_RADIUS = 20 // px
const BORDER_GRADIENT: Gradient[] = [
  {color: '#fff', offset: 0},
  {color: '#bbb', offset: 100},
]

const Toggle: React.FC<ToggleProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {items, onToggle, currentIndex, hasBackground, ariaControls} = initializedProps

  const [isMounted, setMounted] = useState<boolean>(false)
  const [isOverflowing, setIsOverflowing] = useState<boolean>(false)

  const currentIndexRef = useRef<number>(currentIndex)
  const wrapperRef = useRef<HTMLDivElement>(null)
  const contentRef = useRef<HTMLDivElement>(null)
  const selectionRef = useRef<SVGSVGElement>(null)

  const updateSelection = useCallback(() => {
    if (!wrapperRef.current || !contentRef.current || !selectionRef.current) return

    const tabs: NodeListOf<HTMLButtonElement> = wrapperRef.current.querySelectorAll('[role="tab"]')
    const selectedTab = tabs[currentIndexRef.current]
    if (!selectedTab) return

    const selectionRect = selectionRef.current.querySelector('rect')
    if (!selectionRect) return

    // Force a reflow to ensure responsiveness
    selectionRect.style.display = 'none'
    // eslint-disable-next-line @typescript-eslint/no-unused-expressions
    selectionRect.clientHeight
    selectionRect.style.display = ''

    selectionRect.style.width = `${selectedTab.offsetWidth - 2}px`
    selectionRect.style.height = `${selectedTab.offsetHeight - 2}px`
    selectionRect.style.transform = `translate(${selectedTab.offsetLeft}px, ${selectedTab.offsetTop}px)`
  }, [])

  const onClick = useCallback(
    (itemIndex: number) => {
      if (items[itemIndex]) {
        onToggle(items[itemIndex].value)
      }
    },
    [items, onToggle],
  )

  const onSelection = useCallback(
    (newValue: string) => {
      onToggle(newValue)
    },
    [onToggle],
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
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentIndex])

  useEffect(() => {
    setMounted(true)

    const handleResize = () => {
      // Check overflow
      if (contentRef.current) {
        const {scrollWidth, clientWidth} = contentRef.current
        setIsOverflowing(scrollWidth > clientWidth)
      }

      // Update selection if mounted
      if (isMounted && contentRef.current) {
        updateSelection()
      }
    }

    handleResize() // Initial check

    // eslint-disable-next-line github/prefer-observers
    window.addEventListener('resize', handleResize)

    return () => {
      window.removeEventListener('resize', handleResize)
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isMounted])

  return (
    <div ref={wrapperRef} className="Toggle-wrapper">
      {/* Tabs for Desktop */}
      <div
        className={`Toggle-container
          ${hasBackground ? 'Toggle-container--background' : ''} ${isOverflowing ? 'Toggle-container--isHidden' : ''}
        `}
        role="tablist"
        aria-controls={ariaControls}
        aria-hidden={isOverflowing}
      >
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
      </div>

      {/* Menu for Mobile */}
      <div
        className={`${hasBackground ? 'Toggle-menu--background' : ''} ${!isOverflowing ? 'Toggle-menu--isHidden' : ''}`}
        aria-hidden={!isOverflowing}
      >
        <ActionMenu onSelect={newValue => onSelection(newValue)} selectionVariant="single" menuSide="inside-center">
          <ActionMenu.Button aria-label="Select a GitHub feature">{items[currentIndex]?.label}</ActionMenu.Button>
          <ActionMenu.Overlay aria-label="Features">
            {items.map((item, index) => (
              <ActionMenu.Item
                // eslint-disable-next-line @eslint-react/no-array-index-key
                key={`item_${index}`}
                value={item.value}
                selected={currentIndex === index}
              >
                {item.label}
              </ActionMenu.Item>
            ))}
          </ActionMenu.Overlay>
        </ActionMenu>
      </div>
    </div>
  )
}

export default Toggle
