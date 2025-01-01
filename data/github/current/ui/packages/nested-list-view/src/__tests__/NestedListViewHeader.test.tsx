import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {NestedListViewCompletionPill} from '../CompletionPill'
import {NestedListView} from '../NestedListView'
import {NestedListViewHeader} from '../NestedListViewHeader/NestedListViewHeader'
import {NestedListViewHeaderTitle} from '../NestedListViewHeader/Title'

describe('NestedListViewHeader', () => {
  it('renders title and progress', () => {
    render(
      <NestedListView
        title="list"
        header={
          <NestedListViewHeader
            title={<NestedListViewHeaderTitle title="Sub-issues" />}
            completionPill={
              <NestedListViewCompletionPill
                progress={{
                  total: 1,
                  completed: 0,
                  percentCompleted: 0,
                }}
              />
            }
          />
        }
      />,
    )

    expect(screen.getByText('Sub-issues')).toBeInTheDocument()
    expect(screen.getByText('0 of 1')).toBeInTheDocument()
  })

  it('renders section filters', () => {
    render(
      <NestedListView
        title="list"
        header={
          <NestedListViewHeader
            title={<NestedListViewHeaderTitle title="Sub-issues" />}
            sectionFilters={<div>Section filters</div>}
          />
        }
      />,
    )

    expect(screen.getByText('Section filters')).toBeInTheDocument()
  })

  it('renders section filter with links', () => {
    render(
      <NestedListView
        title="list"
        header={
          <NestedListViewHeader
            title={<NestedListViewHeaderTitle title="Sub-issues" />}
            sectionFilters={[<div key="1">Section filter 1</div>, <div key="2">Section filter 2</div>]}
          />
        }
      />,
    )

    expect(screen.getByText('Section filter 1')).toBeInTheDocument()
    expect(screen.getByText('Section filter 2')).toBeInTheDocument()
  })

  it('does not render section filters when empty', () => {
    render(
      <NestedListView
        title="list"
        header={<NestedListViewHeader title={<NestedListViewHeaderTitle title="Sub-issues" />} sectionFilters={[]} />}
      />,
    )

    expect(screen.queryByText('Section filters')).not.toBeInTheDocument()
  })

  it('does not render checkbox when not selectable', () => {
    render(
      <NestedListView
        title="list"
        header={<NestedListViewHeader title={<NestedListViewHeaderTitle title="Sub-issues" />} />}
      />,
    )

    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
  })

  it('renders select all checkbox', () => {
    const onToggleSelectAll = jest.fn()
    render(
      <NestedListView
        title="list"
        isSelectable
        header={
          <NestedListViewHeader title={<NestedListViewHeaderTitle title="Sub-issues" />} onToggleSelectAll={() => {}} />
        }
      />,
    )

    expect(screen.getByRole('checkbox', {name: 'Select all list items: list'})).toBeInTheDocument()
    expect(onToggleSelectAll).not.toHaveBeenCalled()
  })

  it('toggles select all checkbox', () => {
    const onToggleSelectAll = jest.fn()
    render(
      <NestedListView
        title="list"
        isSelectable
        header={
          <NestedListViewHeader
            title={<NestedListViewHeaderTitle title="Sub-issues" />}
            onToggleSelectAll={onToggleSelectAll}
          />
        }
      />,
    )

    const checkbox = screen.getByRole('checkbox', {name: 'Select all list items: list'})
    expect(checkbox).not.toBeChecked()

    checkbox.click()
    expect(onToggleSelectAll).toHaveBeenCalledWith(true)
  })

  it('toggles select all checkbox with space key', async () => {
    const onToggleSelectAll = jest.fn()
    const {user} = render(
      <NestedListView
        title="list"
        isSelectable
        header={
          <NestedListViewHeader
            title={<NestedListViewHeaderTitle title="Sub-issues" />}
            onToggleSelectAll={onToggleSelectAll}
          />
        }
      />,
    )

    const checkbox = screen.getByRole('checkbox', {name: 'Select all list items: list'})
    expect(checkbox).not.toBeChecked()

    checkbox.focus()
    await user.keyboard(' ')

    expect(onToggleSelectAll).toHaveBeenCalledWith(true)
  })

  it('toggles select all checkbox with enter key', async () => {
    const onToggleSelectAll = jest.fn()
    const {user} = render(
      <NestedListView
        title="list"
        isSelectable
        header={
          <NestedListViewHeader
            title={<NestedListViewHeaderTitle title="Sub-issues" />}
            onToggleSelectAll={onToggleSelectAll}
          />
        }
      />,
    )

    const checkbox = screen.getByRole('checkbox', {name: 'Select all list items: list'})
    expect(checkbox).not.toBeChecked()

    checkbox.focus()
    await user.keyboard('[Enter]')

    expect(onToggleSelectAll).toHaveBeenCalledWith(true)
  })

  it('renders expand button', () => {
    render(
      <NestedListView
        title="list"
        isCollapsible
        header={<NestedListViewHeader title={<NestedListViewHeaderTitle title="Sub-issues" />} />}
      />,
    )

    expect(screen.getByRole('button', {name: 'Collapse Sub-issues'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Collapse Sub-issues'})).toHaveAttribute('aria-expanded', 'true')
  })

  it('toggles expand button', async () => {
    const {user} = render(
      <NestedListView
        title="list"
        isCollapsible
        header={<NestedListViewHeader title={<NestedListViewHeaderTitle title="Sub-issues" />} />}
      />,
    )

    const button = screen.getByRole('button', {name: 'Collapse Sub-issues'})
    expect(button).toHaveAttribute('aria-expanded', 'true')
    await user.click(button)
    expect(button).toHaveAttribute('aria-expanded', 'false')
    expect(screen.getByRole('button', {name: 'Expand Sub-issues'})).toBeInTheDocument()
  })
})
