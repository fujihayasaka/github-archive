import {noop} from '@github-ui/noop'
import {act, screen} from '@testing-library/react'
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

  it('does not render sub-issue conversion for pull requests', async () => {
    const item = {
      title: `https://github.com/github/yay/pull/2`,
      position: [0, 0],
      id: `0`,
      index: 0,
      children: [],
      nested: false,
      content: '<span class="reference"><a href="https://github.com/github/yay/pull/2">github/yay#2</a></span>',
      checked: false,

      container: document.createElement('li'),
      markdownIndex: 0,
    } as TaskItem
    render(<TaskListItemWrapper item={item} />)

    const menuButton = await screen.findByTestId('tasklist-item-1-0-menu')
    expect(menuButton).toBeInTheDocument()
    act(() => {
      menuButton.click()
    })
    const subIssueConvertButton = screen.queryByTestId('tasklist-item-1-0-menu-convert-sub-issue')
    expect(subIssueConvertButton).not.toBeInTheDocument()
    const issueConvertButton = screen.queryByTestId('tasklist-item-1-0-menu-convert')
    expect(issueConvertButton).not.toBeInTheDocument()
  })

  it('does render sub-issue conversion for issues', async () => {
    const item = {
      title: `https://github.com/github/issues/1`,
      position: [0, 0],
      id: `0`,
      index: 0,
      children: [],
      nested: false,
      content: '<span class="reference"><a href="https://github.com/github/yay/issues/1">github/yay#1</a></span>',
      checked: false,

      container: document.createElement('li'),
      markdownIndex: 0,
    } as TaskItem
    render(<TaskListItemWrapper item={item} />)

    const menuButton = await screen.findByTestId('tasklist-item-1-0-menu')
    expect(menuButton).toBeInTheDocument()
    act(() => {
      menuButton.click()
    })

    const subIssueConvertButton = screen.queryByTestId('tasklist-item-1-0-menu-convert-sub-issue')
    expect(subIssueConvertButton).toBeInTheDocument()
    const issueConvertButton = screen.queryByTestId('tasklist-item-1-0-menu-convert')
    expect(issueConvertButton).not.toBeInTheDocument()
  })

  it('does not render sub-issue conversion for mixed content', async () => {
    const item = {
      title: `I am text https://github.com/github/issues/1`,
      position: [0, 0],
      id: `0`,
      index: 0,
      children: [],
      nested: false,
      content: 'I am text <span class="reference">https://github.com/github/issues/1</span>',
      checked: false,

      container: document.createElement('li'),
      markdownIndex: 0,
    } as TaskItem
    render(<TaskListItemWrapper item={item} />)

    const menuButton = await screen.findByTestId('tasklist-item-1-0-menu')
    expect(menuButton).toBeInTheDocument()
    act(() => {
      menuButton.click()
    })
    const subIssueConvertButton = screen.queryByTestId('tasklist-item-1-0-menu-convert-sub-issue')
    expect(subIssueConvertButton).not.toBeInTheDocument()
    const issueConvertButton = screen.queryByTestId('tasklist-item-1-0-menu-convert')
    expect(issueConvertButton).not.toBeInTheDocument()
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
          onConvertToSubIssue={noop}
          hideActions={hideActions}
          disabled={disabled}
        />
      </DragAndDrop.Item>
    </DragAndDrop>
  )
}
