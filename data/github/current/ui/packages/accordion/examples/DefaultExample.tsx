import {useState} from 'react'
import {Accordion} from '../Accordion'

export default function DefaultExample() {
  const [expandedItems, setExpandedItems] = useState<string[]>([])

  return (
    <Accordion expandedItems={expandedItems} onChange={setExpandedItems}>
      <Accordion.Item value="item1">
        <Accordion.Trigger>Item 1</Accordion.Trigger>
        <Accordion.Content>Content for Item 1</Accordion.Content>
      </Accordion.Item>
      <Accordion.Item value="item2">
        <Accordion.Trigger>Item 2</Accordion.Trigger>
        <Accordion.Content>Content for Item 2</Accordion.Content>
      </Accordion.Item>
      <Accordion.Item value="item3">
        <Accordion.Trigger>Item 3</Accordion.Trigger>
        <Accordion.Content>Content for Item 3</Accordion.Content>
      </Accordion.Item>
    </Accordion>
  )
}
