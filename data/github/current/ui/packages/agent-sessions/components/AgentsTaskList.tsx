import {ListView} from '@github-ui/list-view'
import {AgentsTaskListItem, type AgentsTaskListItemProps} from './AgentsTaskListItem'

export function AgentsTaskList({items}: {items: AgentsTaskListItemProps[]}): JSX.Element {
  return (
    <ListView title="Pull Requests">
      {items.map(item => (
        <AgentsTaskListItem key={item.pullRequest.id} {...item} />
      ))}
    </ListView>
  )
}
