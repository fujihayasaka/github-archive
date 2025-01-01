import {noop} from '@github-ui/noop'
import {screen} from '@testing-library/react'
import {TaskListItem, type TaskListItemProps} from '../components/TaskListItem'
import {createItem} from '../test-utils/helpers'
import type {TaskItem} from '../constants/types'
import {render} from '@github-ui/react-core/test-utils'
import {DragAndDrop} from '@github-ui/drag-and-drop'

const items = [0, 1, 2].map(item => createItem(item, item))

describe('TaskListItem', () => {
  it('renders as enabled when viewer has permission to update and component is not updating', () => {
    render(<TaskListItemWrapper item={items[0] as TaskItem} disabled={false} hideActions={false} />)

    const menuButton = screen.getByLabelText('Open item 1 task options')
    expect(menuButton).toBeInTheDocument()
    expect(menuButton).not.toHaveAttribute('disabled')
  })

  it('renders as disabled when viewer has permission to update and component is updating', () => {
    render(<TaskListItemWrapper item={items[0] as TaskItem} disabled hideActions={false} />)

    const menuButton = screen.getByLabelText('Open item 1 task options')
    expect(menuButton).toBeInTheDocument()
    expect(menuButton).toHaveAttribute('disabled')
  })

  it('does not render when viewer does not have permission to update', () => {
    render(<TaskListItemWrapper item={items[0] as TaskItem} disabled hideActions />)

    const menuButton = screen.queryByLabelText('Open item 1 task options')
    expect(menuButton).not.toBeInTheDocument()
  })
})

const TaskListItemWrapper = ({
  item,
  disabled = false,
  hideActions = false,
}: Pick<TaskListItemProps, 'item' | 'disabled' | 'hideActions'>) => {
  return (
    <DragAndDrop items={[]} onDrop={noop} renderOverlay={() => <></>}>
      <DragAndDrop.Item id={item.id} title={item.title} index={item.index}>
        <TaskListItem
          markdownValue={''}
          onChange={noop}
          totalItems={3}
          item={item}
          onConvertToIssue={noop}
          hideActions={hideActions}
          disabled={disabled}
        />
      </DragAndDrop.Item>
    </DragAndDrop>
  )
}
