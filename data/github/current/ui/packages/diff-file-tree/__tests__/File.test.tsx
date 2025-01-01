import {act, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {File} from '../DiffFileTree'
import {type DiffDelta, FileNode} from '../diff-file-tree-helpers'

const mockFile = new FileNode<DiffDelta>({
  path: 'path/to/test.txt',
  pathDigest: 'abc123',
  changeType: 'modified',
  totalCommentsCount: 0,
})

describe('File component', () => {
  let mockOnSelect: jest.Mock

  beforeEach(() => {
    mockOnSelect = jest.fn()
    // Mock window.open
    window.open = jest.fn()
  })

  it('renders file name as a link with correct href', () => {
    render(<File file={mockFile} depth={1} hash="" onSelect={mockOnSelect} />)

    const link = screen.getByRole('presentation')
    expect(link).toHaveAttribute('href', '#diff-abc123')
    expect(link).toHaveTextContent('test.txt')
  })

  it('regular click of the tree item calls onSelect and delegates event to link', async () => {
    const mockClick = jest.fn()
    const {user} = render(<File file={mockFile} depth={1} hash="" onSelect={mockOnSelect} />)

    const link = screen.getByRole('presentation')
    link.onclick = mockClick

    const treeItem = screen.getByRole('treeitem')
    await user.click(treeItem)

    expect(mockOnSelect).toHaveBeenCalledWith(mockFile.diff)
    expect(mockClick).toHaveBeenCalled()
  })

  it('opens in new tab on ctrl+click of the tree item', async () => {
    const {user} = render(<File file={mockFile} depth={1} hash="" onSelect={mockOnSelect} />)

    const treeItem = screen.getByRole('treeitem')

    await user.keyboard('[ControlLeft>]')
    await user.click(treeItem)
    await user.keyboard('[/ControlLeft]')

    expect(window.open).toHaveBeenCalledWith('#diff-abc123', '_blank')
  })

  it('opens in new tab on meta+click of the tree item', async () => {
    const {user} = render(<File file={mockFile} depth={1} hash="" onSelect={mockOnSelect} />)

    const treeItem = screen.getByRole('treeitem')

    await user.keyboard('[MetaLeft>]')
    await user.click(treeItem)
    await user.keyboard('[/MetaLeft]')

    expect(window.open).toHaveBeenCalledWith('#diff-abc123', '_blank')
  })

  it('opens in new tab on middle click of the tree item', async () => {
    const {user} = render(<File file={mockFile} depth={1} hash="" onSelect={mockOnSelect} />)

    const treeItem = screen.getByRole('treeitem')
    await user.pointer({keys: '[MouseMiddle]', target: treeItem})

    expect(window.open).toHaveBeenCalledWith('#diff-abc123', '_blank')
  })

  it('Enter key press of the tree item calls onSelect and delegates event to link', async () => {
    const mockClick = jest.fn()
    const {user} = render(<File file={mockFile} depth={1} hash="" onSelect={mockOnSelect} />)

    const link = screen.getByRole('presentation')
    link.onclick = mockClick

    const treeItem = screen.getByRole('treeitem')

    act(() => {
      treeItem.focus()
    })

    await user.keyboard('[Enter]')

    expect(mockOnSelect).toHaveBeenCalledWith(mockFile.diff)
    expect(mockClick).toHaveBeenCalled()
  })

  it('Space key press of the tree item calls onSelect and delegates event to link', async () => {
    const mockClick = jest.fn()
    const {user} = render(<File file={mockFile} depth={1} hash="" onSelect={mockOnSelect} />)

    const link = screen.getByRole('presentation')
    link.onclick = mockClick

    const treeItem = screen.getByRole('treeitem')

    act(() => {
      treeItem.focus()
    })

    await user.keyboard('[Space]')

    expect(mockOnSelect).toHaveBeenCalledWith(mockFile.diff)
    expect(mockClick).toHaveBeenCalled()
  })

  it('verifies link accessibility attributes', () => {
    render(<File file={mockFile} depth={1} hash="" onSelect={mockOnSelect} />)

    const link = screen.getByRole('presentation')
    expect(link).toHaveAttribute('role', 'presentation')
    expect(link).toHaveAttribute('tabIndex', '-1')
  })
})
