import type React from 'react'
import {useEffect, useRef, useState, useMemo} from 'react'
import {ActionMenu, Heading, Text} from '@primer/react-brand'

interface PricingListProps {
  children: React.ReactNode
  responsiveMenu?: string[]
}

interface PricingListColumnProps {
  children: React.ReactNode
}

interface PricingListHeadingProps {
  children: React.ReactNode
}

interface PricingListListProps {
  children: React.ReactNode
}

interface PricingListItemProps {
  children: React.ReactNode
  leadingText?: string
  trailingText?: string
}

// PricingList

const PricingList: React.FC<PricingListProps> & {
  Column: React.FC<PricingListColumnProps>
  Heading: React.FC<PricingListHeadingProps>
  List: React.FC<PricingListListProps>
  Item: React.FC<PricingListItemProps>
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
} = ({children, responsiveMenu = []}) => {
  const [selection, setSelection] = useState(responsiveMenu[0] ?? '')
  const pricingListRef = useRef<HTMLDivElement>(null)

  // Toggle visibility of columns based on selection
  useEffect(() => {
    const container = pricingListRef.current
    if (container && responsiveMenu.length > 0) {
      for (const [index, child] of Array.from(container.children).entries()) {
        if (selection === responsiveMenu[index]) {
          child.classList.add('isVisible')
        } else {
          child.classList.remove('isVisible')
        }
      }
    }
  }, [selection, responsiveMenu])

  const menuItems = useMemo(
    () =>
      responsiveMenu.map(heading => (
        <ActionMenu.Item key={heading} value={heading} selected={heading === selection}>
          {heading}
        </ActionMenu.Item>
      )),
    [responsiveMenu, selection],
  )

  return (
    <div className="PricingList">
      {/* Show menu on mobile */}
      {responsiveMenu.length > 0 && (
        <ActionMenu onSelect={newValue => setSelection(newValue)} selectionVariant="single">
          <ActionMenu.Button className="PricingList-button" aria-label="Select an option">
            {selection}
          </ActionMenu.Button>
          <ActionMenu.Overlay aria-label="Options">{menuItems}</ActionMenu.Overlay>
        </ActionMenu>
      )}

      <div className="PricingList-container" ref={pricingListRef}>
        {children}
      </div>
    </div>
  )
}

// Column

const PricingListColumn: React.FC<{children: React.ReactNode}> = ({children}) => {
  return <div className="PricingList-column">{children}</div>
}
PricingListColumn.displayName = 'PricingListColumn'
PricingList.Column = PricingListColumn

// Heading

const PricingListHeading: React.FC<{children: React.ReactNode}> = ({children, ...props}) => {
  return (
    <Heading className="PricingList-heading" as="h3" size="6" {...props}>
      {children}
    </Heading>
  )
}
PricingListHeading.displayName = 'PricingListHeading'
PricingList.Heading = PricingListHeading

// List

const PricingListList: React.FC<{children: React.ReactNode}> = ({children}) => {
  return <ul className="PricingList-list">{children}</ul>
}
PricingListList.displayName = 'PricingListList'
PricingList.List = PricingListList

// Item

const PricingListItem: React.FC<{children: React.ReactNode; leadingText?: string; trailingText?: string}> = ({
  children,
  leadingText,
  trailingText,
}) => {
  return (
    <li className="PricingList-item">
      {leadingText && (
        <Text className="PricingList-leadingText" as="div" variant="muted">
          {leadingText}
        </Text>
      )}

      <Text as="div" weight="bold">
        {children}
      </Text>

      {trailingText && (
        <Text className="PricingList-trailingText" as="div" variant="muted" size="100">
          {trailingText}
        </Text>
      )}
    </li>
  )
}
PricingListItem.displayName = 'PricingListItem'
PricingList.Item = PricingListItem

export default PricingList
