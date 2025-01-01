import {LinkExternalIcon} from '@primer/octicons-react'
import {ActionList, type ActionListItemProps} from '@primer/react'
import {clsx} from 'clsx'
import {useId} from 'react'

interface LinkSuggestionProps extends ActionListItemProps {
  leadingVisual?: React.ReactNode
}

export function LinkSuggestion({leadingVisual, ...props}: LinkSuggestionProps) {
  const nameId = useId()
  const hintId = useId()

  return (
    <ActionList.Item {...props} aria-labelledby={clsx(nameId, hintId)}>
      {leadingVisual !== undefined && <ActionList.LeadingVisual>{leadingVisual}</ActionList.LeadingVisual>}
      <span id={nameId}>{props.children}</span>
      <span className="d-none" aria-hidden id={hintId}>
        Opens in new tab.
      </span>
      <ActionList.TrailingVisual>
        <LinkExternalIcon />
      </ActionList.TrailingVisual>
    </ActionList.Item>
  )
}
