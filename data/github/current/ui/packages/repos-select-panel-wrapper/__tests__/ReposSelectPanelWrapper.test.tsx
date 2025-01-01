import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'
import {FileIcon} from '@primer/octicons-react'

import {ReposSelectPanelWrapper, type ReposSelectPanelWrapperItem} from '../ReposSelectPanelWrapper'

const sampleItems: ReposSelectPanelWrapperItem[] = [
  {text: 'Foo', id: 'foo'},
  {text: 'Bar', id: 'bar'},
  {text: 'Baz', id: 'baz'},
]

const sampleProps: React.ComponentProps<typeof ReposSelectPanelWrapper> = {
  title: 'TestLabel',
  inputLabel: 'label',
  items: sampleItems,
  selectedItem: sampleItems[1]!,
  onSelect: jest.fn(),
  placeholderText: 'Search',
  anchorButtonSelectedIcon: FileIcon,
  anchorButtonDescribedBy: '',
  textInputLabelledBy: '',
}

describe('SelectPanelWrapper', () => {
  test('filters items', async () => {
    const {user} = render(<ReposSelectPanelWrapper {...sampleProps} />)

    await user.click(screen.getByRole('button'))
    await screen.findByRole('dialog')

    // can't use getByText, because 'Bar' matches both the button and the list item
    const itemsBefore = screen.queryAllByRole('option')
    expect(itemsBefore[0]).toHaveTextContent('Bar')
    expect(itemsBefore[1]).toHaveTextContent('Foo')
    expect(itemsBefore[2]).toHaveTextContent('Baz')

    await user.type(screen.getByRole('textbox'), 'foo')

    // Bar is still present because the selected item should always be visible
    const itemsAfter = screen.queryAllByRole('option')
    expect(itemsAfter[0]).toHaveTextContent('Bar')
    expect(itemsAfter[1]).toHaveTextContent('Foo')
    expect(screen.queryByText('Baz')).not.toBeInTheDocument()
  })

  test('selected item is always displayed first, and button displays selected text', async () => {
    const {user} = render(<ReposSelectPanelWrapper {...sampleProps} selectedItem={sampleItems[2]!} />)

    expect(screen.getByRole('button')).toHaveTextContent('Baz')

    await user.click(screen.getByRole('button'))
    await screen.findByRole('dialog')

    const items = screen.queryAllByRole('option')
    expect(items[0]).toHaveTextContent('Baz')
    expect(items[0]).toHaveAttribute('aria-selected', 'true')

    expect(items[1]).toHaveTextContent('Foo')
    expect(items[2]).toHaveTextContent('Bar')
  })

  test('cannot deselect item', async () => {
    const {user} = render(<ReposSelectPanelWrapper {...sampleProps} />)

    await user.click(screen.getByRole('button'))
    await screen.findByRole('dialog')

    const items = screen.queryAllByRole('option')
    expect(items[0]).toHaveAttribute('aria-selected', 'true')
    await user.click(items[0]!)

    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    })

    expect(sampleProps.onSelect).not.toHaveBeenCalled()
  })
})
