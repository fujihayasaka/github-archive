import {ArrowRightIcon} from '@primer/octicons-react'
import {ActionList, type ActionListItemProps} from '@primer/react'

interface MultistepSuggestionProps extends ActionListItemProps {
  leadingVisual?: React.ReactNode
}

export function MultistepSuggestion({leadingVisual, ...props}: MultistepSuggestionProps) {
  return (
    <ActionList.Item aria-haspopup {...props}>
      {leadingVisual !== undefined && <ActionList.LeadingVisual>{leadingVisual}</ActionList.LeadingVisual>}
      {props.children}
      <ActionList.TrailingVisual>
        <ArrowRightIcon />
      </ActionList.TrailingVisual>
    </ActionList.Item>
  )
}
