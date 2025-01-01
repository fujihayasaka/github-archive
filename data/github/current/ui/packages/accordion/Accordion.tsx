import React from 'react'
import {ChevronDownIcon} from '@primer/octicons-react'
import styles from './Accordion.module.css'

type AccordionContextType = {
  expandedItems: string[]
  toggleItem: (value: string) => void
  currentValue?: string
}

const AccordionContext = React.createContext<AccordionContextType | undefined>(undefined)

// Add base interface for shared props
interface BaseProps {
  className?: string
  children: React.ReactNode
}

interface AccordionProps extends BaseProps {
  expandedItems: string[]
  onChange: (expandedItems: string[]) => void
  'data-testid'?: string
}

export function Accordion({children, expandedItems, onChange, className, 'data-testid': testId}: AccordionProps) {
  const toggleItem = React.useCallback(
    (id: string) => {
      const newExpanded = expandedItems.includes(id)
        ? expandedItems.filter(item => item !== id)
        : [...expandedItems, id]
      onChange(newExpanded)
    },
    [expandedItems, onChange],
  )

  const contextValue = React.useMemo(() => ({expandedItems, toggleItem}), [expandedItems, toggleItem])

  return (
    <AccordionContext.Provider value={contextValue}>
      <div className={`${styles.accordion} ${className || ''}`} data-testid={testId}>
        {children}
      </div>
    </AccordionContext.Provider>
  )
}

interface ItemProps extends BaseProps {
  value: string
}

function AccordionItem({children, value, className}: ItemProps) {
  const context = React.useContext(AccordionContext)

  const itemContextValue = React.useMemo(
    () => ({
      expandedItems: context?.expandedItems ?? [],
      toggleItem: context?.toggleItem ?? (() => {}),
      currentValue: value,
    }),
    [context?.expandedItems, context?.toggleItem, value],
  )

  return (
    <AccordionContext.Provider value={itemContextValue}>
      <div className={`${styles.item} ${className || ''}`}>{children}</div>
    </AccordionContext.Provider>
  )
}

interface TriggerProps extends BaseProps {
  id?: string
}

function AccordionTrigger({children, className, id}: TriggerProps) {
  const context = React.useContext(AccordionContext)
  if (!context) throw new Error('AccordionTrigger must be used within an Accordion')
  if (!context.currentValue) throw new Error('AccordionTrigger must be used within AccordionItem')

  const isExpanded = context.expandedItems.includes(context.currentValue)
  const triggerId = id || `trigger-${context.currentValue}`

  return (
    <button
      id={triggerId}
      className={`${styles.trigger} ${className || ''}`}
      onClick={() => context.currentValue && context.toggleItem(context.currentValue)}
      aria-expanded={isExpanded}
      aria-controls={`content-${context.currentValue}`}
      type="button"
    >
      <span className={styles.triggerText}>{children}</span>
      <ChevronDownIcon className={`${styles.icon} ${isExpanded ? styles.iconExpanded : ''}`} aria-hidden="true" />
    </button>
  )
}

interface ContentProps extends BaseProps {}

function AccordionContent({children, className}: ContentProps) {
  const context = React.useContext(AccordionContext)
  if (!context) throw new Error('AccordionContent must be used within an Accordion')
  if (!context.currentValue) throw new Error('AccordionContent must be used within AccordionItem')

  const isExpanded = context.expandedItems.includes(context.currentValue)
  const triggerId = `trigger-${context.currentValue}`

  return (
    <div
      id={`content-${context.currentValue}`}
      className={`${styles.content} ${className || ''}`}
      hidden={!isExpanded}
      role="region"
      aria-labelledby={triggerId}
    >
      {children}
    </div>
  )
}

Accordion.Item = AccordionItem
Accordion.Trigger = AccordionTrigger
Accordion.Content = AccordionContent

export default Accordion
