import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {DraftIssueTreeBlock} from '../DraftIssueTreeBlock'

const mockContentPreviewContext = {
  items: new Map(),
  versionedItems: new Map(),
  updateItem: jest.fn(),
  openItem: jest.fn(),
  closeItem: jest.fn(),
  openPreviewPane: jest.fn(),
}
jest.mock('../../../../components/ContentPreview/ContentPreviewContext', () => ({
  useContentPreview: jest.fn(() => mockContentPreviewContext),
}))

const mockContentPreviewBlockContext = {
  messageId: 'message-id',
  messageIndex: 1,
  autoOpenPreviewPane: true,
  hasAutoOpenedPreviewPaneRef: {current: false},
}
jest.mock('../../../ContentPreviewBlockContext', () => ({
  useContentPreviewBlockContext: jest.fn(() => mockContentPreviewBlockContext),
}))

const mockData = `
title: Epic 1
tag: epic-1
---
title: Feature 1.1
tag: feature-1.1
parentTag: epic-1
---
title: Task 1.1.1
tag: task-1.1.1
parentTag: feature-1.1
`

describe('DraftIssueTreeBlock', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    mockContentPreviewBlockContext.hasAutoOpenedPreviewPaneRef.current = false
  })

  it('renders a complete tree', () => {
    render(<DraftIssueTreeBlock isStreaming={false} data={mockData} />)

    expect(screen.getByRole('tree')).toBeInTheDocument()
    expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    expect(screen.getByRole('treeitem', {name: /Epic 1/})).toBeInTheDocument()
    expect(screen.getByRole('treeitem', {name: /Feature 1.1/})).toBeInTheDocument()
    expect(screen.getByRole('treeitem', {name: /Task 1.1.1/})).toBeInTheDocument()
  })

  it('renders with loading spinner while streaming', () => {
    render(<DraftIssueTreeBlock isStreaming data={mockData} />)

    expect(screen.getByRole('tree')).toBeInTheDocument()
    expect(screen.getAllByText('Loading').length).toBe(3)
  })

  it('updates the tree items in the content preview context', () => {
    render(<DraftIssueTreeBlock isStreaming={false} data={mockData} />)

    expect(mockContentPreviewContext.updateItem).toHaveBeenCalledWith(
      expect.objectContaining({
        id: `new-issue:epic-1#${mockContentPreviewBlockContext.messageIndex}`,
      }),
    )
    expect(mockContentPreviewContext.updateItem).toHaveBeenCalledWith(
      expect.objectContaining({
        id: `new-issue:feature-1.1#${mockContentPreviewBlockContext.messageIndex}`,
      }),
    )
    expect(mockContentPreviewContext.updateItem).toHaveBeenCalledWith(
      expect.objectContaining({
        id: `new-issue:task-1.1.1#${mockContentPreviewBlockContext.messageIndex}`,
      }),
    )
  })

  it('renders the version label when an item has versions', () => {
    const baseId = `new-issue:epic-1`
    mockContentPreviewContext.versionedItems.set(baseId, [`${baseId}#1`, `${baseId}#2`])

    render(<DraftIssueTreeBlock isStreaming={false} data={mockData} />)

    const epic = screen.getByRole('treeitem', {name: /Epic 1/})
    expect(epic).toBeInTheDocument()
    expect(epic).toHaveTextContent('v1')
  })

  it('auto-opens the top-level items while streaming', () => {
    mockContentPreviewBlockContext.autoOpenPreviewPane = true

    render(<DraftIssueTreeBlock isStreaming data={mockData} />)

    expect(mockContentPreviewContext.openItem).toHaveBeenCalledWith(
      `new-issue:epic-1#${mockContentPreviewBlockContext.messageIndex}`,
      false,
    )
    expect(mockContentPreviewContext.openPreviewPane).toHaveBeenCalled()
    expect(mockContentPreviewBlockContext.hasAutoOpenedPreviewPaneRef.current).toBe(true)
  })

  it('does not auto-open the top-level items when not streaming', () => {
    render(<DraftIssueTreeBlock isStreaming={false} data={mockData} />)

    expect(mockContentPreviewContext.openItem).not.toHaveBeenCalled()
    expect(mockContentPreviewContext.openPreviewPane).not.toHaveBeenCalled()
    expect(mockContentPreviewBlockContext.hasAutoOpenedPreviewPaneRef.current).toBe(false)
  })

  it('does not auto-open the top-level items when auto-open is not available', () => {
    mockContentPreviewBlockContext.autoOpenPreviewPane = false

    render(<DraftIssueTreeBlock isStreaming data={mockData} />)

    expect(mockContentPreviewContext.openItem).toHaveBeenCalledWith(
      `new-issue:epic-1#${mockContentPreviewBlockContext.messageIndex}`,
      false,
    )
    expect(mockContentPreviewContext.openPreviewPane).not.toHaveBeenCalled()
    expect(mockContentPreviewBlockContext.hasAutoOpenedPreviewPaneRef.current).toBe(false)
  })

  it('opens the preview pane when an item is clicked', async () => {
    const {user} = render(<DraftIssueTreeBlock isStreaming data={mockData} />)

    const feature = screen.getByText('Feature 1.1')
    expect(feature).toBeInTheDocument()

    await user.click(feature)

    expect(mockContentPreviewContext.openItem).toHaveBeenCalledWith(
      `new-issue:feature-1.1#${mockContentPreviewBlockContext.messageIndex}`,
      true,
    )
    expect(mockContentPreviewContext.openPreviewPane).toHaveBeenCalled()
  })

  describe('with empty data', () => {
    const mockEmptyData = ``

    it('renders an empty tree', () => {
      render(<DraftIssueTreeBlock isStreaming={false} data={mockEmptyData} />)

      expect(screen.queryByRole('tree')).not.toBeInTheDocument()
    })
  })

  describe('with invalid data', () => {
    const mockInvalidData = `
title: Epic 1
# missing tag
---
title: Feature 1.1
# missing tag
parentTag: epic-1
---
`

    it('renders an empty tree', () => {
      render(<DraftIssueTreeBlock isStreaming={false} data={mockInvalidData} />)

      expect(screen.queryByRole('tree')).not.toBeInTheDocument()
    })
  })

  describe('with mixed valid and invalid data', () => {
    const mockMixedData = `
title: Epic 1
tag: epic-1
---
title: Feature 1.1
# missing tag
parentTag: epic-1
---
title: Task 1.1.1
tag: task-1.1.1
parentTag: feature-1.1
`

    it('renders valid elements before break', () => {
      render(<DraftIssueTreeBlock isStreaming={false} data={mockMixedData} />)

      expect(screen.getByRole('treeitem', {name: /Epic 1/})).toBeInTheDocument()
      // When the tree is broken, we can't render anything downstream
      // Make sure that was the only treeitem we have
      expect(screen.getAllByRole('treeitem').length).toBe(1)
    })
  })

  describe('with invalid parent reference', () => {
    const mockInvalidData = `
title: Epic 1
tag: epic-1
---
title: Feature 1.1
tag: feature-1.1
parentTag: epic-2  # pointing to a non-existing parent
---
title: Task 1.1.1
tag: task-1.1.1
parentTag: feature-1.1
`

    it('renders valid elements before break', () => {
      render(<DraftIssueTreeBlock isStreaming={false} data={mockInvalidData} />)

      expect(screen.getByRole('treeitem', {name: /Epic 1/})).toBeInTheDocument()
      // When the tree is broken, we can't render anything downstream
      // Make sure that was the only treeitem we have
      expect(screen.getAllByRole('treeitem').length).toBe(1)
    })
  })

  describe('with circular reference', () => {
    const mockInvalidData = `
title: Epic 1
tag: epic-1
parentTag: task-1.1.1
---
title: Feature 1.1
tag: feature-1.1
parentTag: epic-1
---
title: Task 1.1.1
tag: task-1.1.1
parentTag: feature-1.1
`

    it('renders an empty tree', () => {
      render(<DraftIssueTreeBlock isStreaming={false} data={mockInvalidData} />)

      // Because there are no nodes without a parentTag, there's no "root" node
      expect(screen.queryByRole('tree')).not.toBeInTheDocument()
    })
  })
})
