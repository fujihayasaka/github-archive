import {Actions} from './Actions'
import Description from './Description'
import ItemContainer from './ItemContainer'
import LeadingVisual from './LeadingVisual'
import Status from './Status'
import Title from './Title'
import {TrailingActions} from './TrailingActions'

export const SimpleListItem = Object.assign(ItemContainer, {
  Actions,
  Description,
  LeadingVisual,
  TrailingActions,
  Status,
  Title,
})
