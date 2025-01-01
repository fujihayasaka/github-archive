import type {Meta, StoryObj} from '@storybook/react'
import {useMemo, useRef} from 'react'

import {useVirtualWindow, useVirtualWindowDynamic} from './use-virtual-window'

interface StoryProps {
  totalItems: number
}

export default {
  title: 'Utilities/useVirtualWindow',
  argTypes: {
    totalItems: {
      control: {type: 'range', min: 10, max: 100_000, step: 100},
      description: 'Total number of items to render',
    },
  },
  args: {
    totalItems: 100,
  },
} satisfies Meta<StoryProps>

// Using a function to generate heights based on the current totalItems value
const generateItemHeights = (count: number) => Array.from({length: count}, () => Math.floor(Math.random() * 70) + 30)

const VirtualWindow = ({totalItems}: StoryProps) => {
  const parentRef = useRef<HTMLDivElement>(null)

  const virtualizer = useVirtualWindow({
    size: totalItems,
    parentRef,
    estimateSize: useMemo(() => () => 30, []),
  })

  return (
    <div ref={parentRef} data-testid="container">
      <div style={{height: `${virtualizer.totalSize}px`, position: 'relative'}}>
        {virtualizer.virtualItems.map(item => (
          <div
            key={item.index}
            data-testid={`item-${item.index}`}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              transform: `translateY(${item.start}px)`,
              height: `${item.size}px`,
              width: '100%',
              backgroundColor: `hsl(${(item.index * 10) % 360}, 80%, 90%)`,
            }}
          >
            Item {item.index}
          </div>
        ))}
      </div>
    </div>
  )
}

export const UseVirtualWindow: StoryObj<typeof VirtualWindow> = {
  name: 'useVirtualWindow',
  render: args => <VirtualWindow {...args} />,
}

const VirtualWindowDynamic = ({totalItems}: StoryProps) => {
  const parentRef = useRef<HTMLDivElement>(null)

  // Generate random heights between 30 and 100 pixels for each item
  const itemHeights = useMemo(() => generateItemHeights(totalItems), [totalItems])

  const virtualizer = useVirtualWindowDynamic({
    size: totalItems,
    parentRef,
    estimateSize: useMemo(() => index => itemHeights[index] || 50, [itemHeights]),
  })

  return (
    <div ref={parentRef} data-testid="container-dynamic">
      <div style={{height: `${virtualizer.totalSize}px`, position: 'relative'}}>
        {virtualizer.virtualItems.map(item => {
          const height = itemHeights[item.index]
          return (
            <div
              key={item.index}
              data-testid={`dynamic-item-${item.index}`}
              data-key={item.index} // Required for ResizeObserver to track this element
              style={{
                position: 'absolute',
                top: 0,
                left: 0,
                transform: `translateY(${item.start}px)`,
                height: `${height}px`,
                backgroundColor: `hsl(${(item.index * 10) % 360}, 80%, 90%)`,
                border: '1px solid #ccc',
                padding: '8px',
                boxSizing: 'border-box',
                width: '100%',
              }}
            >
              Item {item.index} (height: {height}px)
            </div>
          )
        })}
      </div>
    </div>
  )
}

export const UseVirtualWindowDynamic: StoryObj<typeof VirtualWindowDynamic> = {
  name: 'useVirtualWindowDynamic',
  render: args => <VirtualWindowDynamic {...args} />,
}
