import {ActionList} from '@primer/react'
import type {Icon} from '@primer/octicons-react'

interface ResourceListProps {
  linkItems: Array<{
    url: string | undefined
    component: Icon
    text: string
    trailingVisual?: React.ReactNode
  }>
  dangerItems?: Array<{
    onSelect: (() => void) | undefined
    component: Icon
    text: string
  }>
}

export function ResourceList(props: ResourceListProps) {
  const {linkItems, dangerItems} = props

  return (
    // Negative left margin is needed to align the icon with the section heading
    <ActionList variant="full" style={{marginLeft: '-6px'}}>
      {linkItems.map(item => {
        const Icon = item.component
        return (
          item.url && (
            <ActionList.LinkItem key={item.text} href={item.url}>
              <ActionList.LeadingVisual>
                <Icon size={16} />
              </ActionList.LeadingVisual>
              {item.text}
              <ActionList.TrailingVisual>{item.trailingVisual}</ActionList.TrailingVisual>
            </ActionList.LinkItem>
          )
        )
      })}
      {dangerItems &&
        dangerItems.map(item => {
          const Icon = item.component
          return (
            item.onSelect && (
              <ActionList.Item key={item.text} onSelect={item.onSelect} variant="danger">
                <ActionList.LeadingVisual>
                  <Icon size={16} />
                </ActionList.LeadingVisual>
                {item.text}
              </ActionList.Item>
            )
          )
        })}
    </ActionList>
  )
}
