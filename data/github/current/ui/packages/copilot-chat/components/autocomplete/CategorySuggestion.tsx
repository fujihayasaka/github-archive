import type {ActionListItemProps} from '@primer/react'

import type {AutocompleteCategory} from './categories'
import {MultistepSuggestion} from './MultistepSuggestion'

interface CategorySuggestionProps extends ActionListItemProps {
  category: AutocompleteCategory
}

export function CategorySuggestion({category: {name, icon: Icon}, ...props}: CategorySuggestionProps) {
  return (
    <MultistepSuggestion leadingVisual={<Icon />} {...props}>
      {name}
    </MultistepSuggestion>
  )
}
