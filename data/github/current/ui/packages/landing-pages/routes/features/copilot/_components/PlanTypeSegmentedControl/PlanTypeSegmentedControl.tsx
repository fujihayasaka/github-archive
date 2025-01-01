import {useEffect, useMemo, useRef, type KeyboardEvent} from 'react'

import {PLAN_TYPES, type PlanType} from '../../_context/PlanTypeContext'

import styles from './PlanTypeSegmentedControl.module.css'

interface TabItem {
  id: string
  value: PlanType
  label: string
}

const TAB_ITEMS: TabItem[] = [
  {
    id: 'individual-plan-tab',
    value: PLAN_TYPES.Individual,
    label: 'For individuals',
  },
  {
    id: 'business-plan-tab',
    value: PLAN_TYPES.Business,
    label: 'For businesses',
  },
] as const

type Props = {
  value: PlanType
  onChange: (value: PlanType) => void
}

export function PlanTypeSegmentedControl(props: Props) {
  const {value, onChange} = props

  const tabsRef = useRef<Array<HTMLButtonElement | null>>([])
  const isUserInitiatedFocus = useRef<boolean>(false)

  const currentIndex = useMemo(() => TAB_ITEMS.findIndex(item => item.value === value), [value])

  const handleKeyDown = (event: KeyboardEvent<HTMLButtonElement>) => {
    let newIndex: number | null = null

    switch (event.code) {
      case 'ArrowLeft':
        newIndex = currentIndex <= 0 ? TAB_ITEMS.length - 1 : currentIndex - 1
        break
      case 'ArrowRight':
        newIndex = currentIndex >= TAB_ITEMS.length - 1 ? 0 : currentIndex + 1
        break
      case 'Home':
        newIndex = 0
        break
      case 'End':
        newIndex = TAB_ITEMS.length - 1
        break
      default:
        return
    }

    if (newIndex !== null && newIndex !== currentIndex) {
      if (TAB_ITEMS[newIndex]) {
        isUserInitiatedFocus.current = true
        onChange(TAB_ITEMS[newIndex]!.value)
      }

      event.preventDefault()
    }
  }

  useEffect(() => {
    if (isUserInitiatedFocus.current) {
      tabsRef.current[currentIndex]?.focus()
      isUserInitiatedFocus.current = false
    }
  }, [currentIndex])

  return (
    <div className={styles.container} role="tablist" aria-label="Pricing plans">
      {TAB_ITEMS.map((item, index) => (
        <button
          key={item.id}
          className={styles.segment}
          id={item.id}
          onClick={() => onChange(item.value)}
          onKeyDown={handleKeyDown}
          role="tab"
          aria-selected={value === item.value}
          aria-controls={`${item.id}-panel`}
          tabIndex={value === item.value ? 0 : -1}
          ref={el => {
            tabsRef.current[index] = el
          }}
        >
          {item.label}
        </button>
      ))}
    </div>
  )
}
