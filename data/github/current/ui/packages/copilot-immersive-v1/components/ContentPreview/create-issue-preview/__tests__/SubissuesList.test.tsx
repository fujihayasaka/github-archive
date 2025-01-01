import {CopilotChatProvider} from '@github-ui/copilot-chat/CopilotChatContext'
import {getCopilotChatProviderProps} from '@github-ui/copilot-chat/test-utils/mock-data'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {render as innerRender} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'

import {
  type DraftIssue,
  type PreviewableContent,
  type PreviewableContentIdentifier,
  stripVersionFromId,
} from '../../content-preview-types'
import {SubissuesList} from '../SubissuesList'

const mockContentPreviewContext = {
  items: new Map<PreviewableContentIdentifier, PreviewableContent>(),
  versionedItems: new Map<PreviewableContentIdentifier, PreviewableContentIdentifier[]>(),
  openItem: jest.fn(),
  updateItem: jest.fn(),
}
jest.mock('../../ContentPreviewContext', () => ({
  useContentPreview: jest.fn(() => mockContentPreviewContext),
}))

const mockChatManagerContext = {
  sendChatMessage: jest.fn(),
  getSelectedThread: jest.fn().mockReturnValue(null),
}
jest.mock('@github-ui/copilot-chat/CopilotChatManagerContext', () => ({
  ...jest.requireActual('@github-ui/copilot-chat/CopilotChatManagerContext'),
  useChatManager: () => mockChatManagerContext,
}))

function createDraftIssue(tag: string, overrides?: Partial<DraftIssue>): DraftIssue {
  return {
    type: 'new-issue',
    tag,
    id: `new-issue:${tag}#1` as const,
    name: `Draft Issue ${tag}`,
    ...overrides,
  } as DraftIssue
}

function render(ui: React.ReactElement) {
  return innerRender(ui, {
    wrapper: ({children}) => {
      return (
        <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
          {children}
        </CopilotChatProvider>
      )
    },
  })
}

describe('SubissuesList', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    jest.spyOn(copilotFeatureFlags, 'draftIssueTree', 'get').mockReturnValue(true)
    mockContentPreviewContext.items.clear()
    mockContentPreviewContext.versionedItems.clear()
  })

  it('should render nothing if the feature flag is off', () => {
    jest.spyOn(copilotFeatureFlags, 'draftIssueTree', 'get').mockReturnValue(false)

    const parentTag = 'epic-parent'
    const parentId = `new-issue:${parentTag}` as const
    mockContentPreviewContext.items.set(`${parentId}:1`, {name: 'Parent Issue'} as PreviewableContent)
    mockContentPreviewContext.versionedItems.set(parentId, [`${parentId}:1`])

    const issue = {parentTag} as DraftIssue
    const {container} = render(<SubissuesList issue={issue} />)

    expect(container).toBeEmptyDOMElement()
  })

  describe('Child Issues', () => {
    it('should render child issues', () => {
      const parent = createDraftIssue('parent')
      mockContentPreviewContext.items.set(parent.id, parent)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(parent.id), [parent.id])

      const child1 = createDraftIssue('child-1', {parentTag: parent.tag, name: 'Child Issue 1'})
      mockContentPreviewContext.items.set(child1.id, child1)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(child1.id), [child1.id])

      const child2 = createDraftIssue('child-2', {parentTag: parent.tag, name: 'Child Issue 2'})
      mockContentPreviewContext.items.set(child2.id, child2)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(child2.id), [child2.id])

      render(<SubissuesList issue={parent} />)

      expect(screen.getByText('Child Issue 1')).toBeInTheDocument()
      expect(screen.getByText('Child Issue 2')).toBeInTheDocument()
    })

    it('should render even if there are no child issues', () => {
      const epic = createDraftIssue('epic')
      mockContentPreviewContext.items.set(epic.id, epic)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(epic.id), [epic.id])

      render(<SubissuesList issue={epic} />)

      expect(screen.getByRole('tree')).toBeInTheDocument()
      expect(screen.queryByRole('treeitem')).not.toBeInTheDocument()
    })

    it('should render multiple levels of child issues', () => {
      const epic = createDraftIssue('epic')
      mockContentPreviewContext.items.set(epic.id, epic)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(epic.id), [epic.id])

      const feature = createDraftIssue('feature', {parentTag: epic.tag, name: 'Feature Issue 1.1'})
      mockContentPreviewContext.items.set(feature.id, feature)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(feature.id), [feature.id])

      const task = createDraftIssue('task', {parentTag: feature.tag, name: 'Task Issue 1.1.1'})
      mockContentPreviewContext.items.set(task.id, task)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(task.id), [task.id])

      render(<SubissuesList issue={epic} />)

      expect(screen.getByText('Feature Issue 1.1')).toBeInTheDocument()
      expect(screen.getByText('Task Issue 1.1.1')).toBeInTheDocument()
    })

    it('should render the latest version of child issues', () => {
      const parent = createDraftIssue('parent')
      mockContentPreviewContext.items.set(parent.id, parent)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(parent.id), [parent.id])

      const childV1 = createDraftIssue('child-1', {
        parentTag: parent.tag,
        id: 'new-issue:child-1#1',
        name: 'Child Issue Previous',
      })
      const childV2 = createDraftIssue('child-1', {
        parentTag: parent.tag,
        id: 'new-issue:child-1#2',
        name: 'Child Issue Current',
      })
      mockContentPreviewContext.items.set(childV1.id, childV1)
      mockContentPreviewContext.items.set(childV2.id, childV2)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(childV1.id), [childV1.id, childV2.id])

      render(<SubissuesList issue={parent} />)

      expect(screen.queryByText('Child Issue Previous')).not.toBeInTheDocument()
      expect(screen.getByText('Child Issue Current')).toBeInTheDocument()
      expect(screen.getByText('v2')).toBeInTheDocument()
    })

    it('should open the child issue when clicked', async () => {
      const parent = createDraftIssue('parent')
      mockContentPreviewContext.items.set(parent.id, parent)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(parent.id), [parent.id])

      const child1 = createDraftIssue('child-1', {parentTag: parent.tag, name: 'Child Issue 1'})
      mockContentPreviewContext.items.set(child1.id, child1)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(child1.id), [child1.id])

      const {user} = render(<SubissuesList issue={parent} />)

      const button = screen.getByText('Child Issue 1')
      expect(button).toBeInTheDocument()

      await user.click(button)

      expect(mockContentPreviewContext.openItem).toHaveBeenCalledWith(child1.id, true)
    })

    it('should render an action menu for each child issue', () => {
      const epic = createDraftIssue('epic')
      mockContentPreviewContext.items.set(epic.id, epic)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(epic.id), [epic.id])

      const feature = createDraftIssue('feature', {parentTag: epic.tag, name: 'Feature Issue 1.1'})
      mockContentPreviewContext.items.set(feature.id, feature)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(feature.id), [feature.id])

      const task = createDraftIssue('task', {parentTag: feature.tag, name: 'Task Issue 1.1.1'})
      mockContentPreviewContext.items.set(task.id, task)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(task.id), [task.id])

      render(<SubissuesList issue={epic} />)

      for (const issue of [feature, task]) {
        const node = screen.getByRole('treeitem', {name: new RegExp(issue.name)})
        expect(node).toBeInTheDocument()
        // Tree nodes are rendered recursively, so a single item will include overflow menus from it's children.
        expect(within(node).getAllByTestId('overflow-menu-anchor').length).toBeGreaterThanOrEqual(1)
      }
    })

    it('should unlink a sub-issue when the action is triggered', async () => {
      const parent = createDraftIssue('parent')
      mockContentPreviewContext.items.set(parent.id, parent)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(parent.id), [parent.id])

      const child1 = createDraftIssue('child-1', {parentTag: parent.tag, name: 'Child Issue 1'})
      mockContentPreviewContext.items.set(child1.id, child1)
      mockContentPreviewContext.versionedItems.set(stripVersionFromId(child1.id), [child1.id])

      const {user} = render(<SubissuesList issue={parent} />)

      const treeNode = screen.getByRole('treeitem', {name: new RegExp(child1.name)})
      expect(treeNode).toBeInTheDocument()

      const overflowMenu = within(treeNode).getByTestId('overflow-menu-anchor')
      expect(overflowMenu).toBeInTheDocument()

      await user.click(overflowMenu)

      const unlinkAction = screen.getByRole('menuitem', {name: 'Unlink sub-issue'})
      expect(unlinkAction).toBeInTheDocument()

      await user.click(unlinkAction)

      expect(mockContentPreviewContext.updateItem).toHaveBeenCalledWith({
        ...child1,
        parentTag: undefined,
        isUserEdited: false,
      })
      expect(mockChatManagerContext.sendChatMessage).toHaveBeenCalledWith(
        expect.objectContaining({
          content: 'Unlink the sub-issue from its parent issue',
          references: expect.arrayContaining([
            expect.objectContaining({
              type: 'text',
              name: `timeline-event: {"type": "unlink-sub-issue", "markdownContent": "Unlinked sub-issue '${child1.name}'"}`,
            }),
            expect.objectContaining({
              type: 'draft-issue',
              tag: child1.tag,
              parentTag: undefined,
            }),
          ]),
        }),
      )
    })

    describe('link subissue', () => {
      it('should render the button', () => {
        const epic = createDraftIssue('epic')
        mockContentPreviewContext.items.set(epic.id, epic)
        mockContentPreviewContext.versionedItems.set(stripVersionFromId(epic.id), [epic.id])

        render(<SubissuesList issue={epic} />)

        expect(screen.getByRole('button', {name: 'Link sub-issue'})).toBeInTheDocument()
      })

      it('should show a blankslate if there are no eligible sub-issues', async () => {
        const epic = createDraftIssue('epic')
        mockContentPreviewContext.items.set(epic.id, epic)
        mockContentPreviewContext.versionedItems.set(stripVersionFromId(epic.id), [epic.id])

        const {user} = render(<SubissuesList issue={epic} />)

        const addButton = screen.getByRole('button', {name: 'Link sub-issue'})
        await user.click(addButton)

        const dialog = screen.getByRole('dialog', {name: 'Select an issue'})

        expect(within(dialog).queryByRole('option')).not.toBeInTheDocument()
        // TODO figure out how to test the blankslate; component stays in Loading state
        // expect(within(dialog).getByText('No issues found')).toBeInTheDocument()
        // expect(within(dialog).getByText('No issues available to link')).toBeInTheDocument()
      })

      it('should show the eligible sub-issues in the action menu', async () => {
        const epic1 = createDraftIssue('epic-1', {name: 'Epic 1'})
        const feature1 = createDraftIssue('feature-1.1', {name: 'Feature 1.1', parentTag: epic1.tag})
        const task1 = createDraftIssue('task-1.1.1', {name: 'Task 1.1.1', parentTag: feature1.tag})

        const standalone1 = createDraftIssue('standalone-1', {name: 'Standalone 1'})
        const standalone2 = createDraftIssue('standalone-2', {name: 'Standalone 2'})

        const epic2 = createDraftIssue('epic-2', {name: 'Epic 2'})
        const feature2 = createDraftIssue('feature-2.1', {name: 'Feature 2.1', parentTag: epic2.tag})
        const task2 = createDraftIssue('task-2.1.1', {name: 'Task 2.1.1', parentTag: feature2.tag})

        for (const issue of [epic1, feature1, task1, standalone1, standalone2, epic2, feature2, task2]) {
          mockContentPreviewContext.items.set(issue.id, issue)
          mockContentPreviewContext.versionedItems.set(stripVersionFromId(issue.id), [issue.id])
        }

        const {user} = render(<SubissuesList issue={task1} />)

        const addButton = screen.getByRole('button', {name: 'Link sub-issue'})
        expect(addButton).toBeInTheDocument()

        await user.click(addButton)

        const dialog = screen.getByRole('dialog', {name: 'Select an issue'})
        expect(dialog).toBeInTheDocument()

        // ancestors of the current issue should not be shown
        expect(within(dialog).queryByRole('option', {name: epic1.name})).not.toBeInTheDocument()
        expect(within(dialog).queryByRole('option', {name: feature1.name})).not.toBeInTheDocument()
        // the current issue should not be shown
        expect(within(dialog).queryByRole('option', {name: task1.name})).not.toBeInTheDocument()
        // unrelated issues without a parent should be shown
        expect(within(dialog).getByRole('option', {name: standalone1.name})).toBeInTheDocument()
        expect(within(dialog).getByRole('option', {name: standalone2.name})).toBeInTheDocument()
        expect(within(dialog).getByRole('option', {name: epic2.name})).toBeInTheDocument()
        // issues that already have a parent should not be shown
        expect(within(dialog).queryByRole('option', {name: feature2.name})).not.toBeInTheDocument()
        expect(within(dialog).queryByRole('option', {name: task2.name})).not.toBeInTheDocument()
      })

      it('should show a blankslate if the maximum depth is already reached', async () => {
        const level1a = createDraftIssue('a-1')
        const level2a = createDraftIssue('a-2', {parentTag: level1a.tag})
        const level3a = createDraftIssue('a-3', {parentTag: level2a.tag})
        const level4a = createDraftIssue('a-4', {parentTag: level3a.tag})
        const level5a = createDraftIssue('a-5', {parentTag: level4a.tag})
        const level6a = createDraftIssue('a-6', {parentTag: level5a.tag})
        const level7a = createDraftIssue('a-7', {parentTag: level6a.tag})

        const level1b = createDraftIssue('b-1')

        for (const issue of [level1a, level2a, level3a, level4a, level5a, level6a, level7a, level1b]) {
          mockContentPreviewContext.items.set(issue.id, issue)
          mockContentPreviewContext.versionedItems.set(stripVersionFromId(issue.id), [issue.id])
        }

        const {user} = render(<SubissuesList issue={level7a} />)

        const addButton = screen.getByRole('button', {name: 'Link sub-issue'})
        await user.click(addButton)
        const dialog = screen.getByRole('dialog', {name: 'Select an issue'})

        // The only eligible option would be `b-1`, but we're already at the maximum depth
        expect(within(dialog).queryByRole('option')).not.toBeInTheDocument()
        // TODO figure out how to test the blankslate; component stays in Loading state
        // expect(within(dialog).getByText('Sub-issue limit reached')).toBeInTheDocument()
      })

      it('should not show nodes that would exceed the maximum depth of the tree', async () => {
        const level1a = createDraftIssue('a-1')
        const level2a = createDraftIssue('a-2', {parentTag: level1a.tag})
        const level3a = createDraftIssue('a-3', {parentTag: level2a.tag})
        const level4a = createDraftIssue('a-4', {parentTag: level3a.tag})

        const level1b = createDraftIssue('b-1')
        const level2b = createDraftIssue('b-2', {parentTag: level1b.tag})
        const level3b = createDraftIssue('b-3', {parentTag: level2b.tag})
        const level4b = createDraftIssue('b-4', {parentTag: level3b.tag})

        for (const issue of [level1a, level2a, level3a, level4a, level1b, level2b, level3b, level4b]) {
          mockContentPreviewContext.items.set(issue.id, issue)
          mockContentPreviewContext.versionedItems.set(stripVersionFromId(issue.id), [issue.id])
        }

        const {user, rerender} = render(<SubissuesList issue={level4a} />)

        {
          const addButton = screen.getByRole('button', {name: 'Link sub-issue'})
          await user.click(addButton)
          const dialog = screen.getByRole('dialog', {name: 'Select an issue'})

          // The only eligible option would be `b-1`, but that would put us over the max depth
          expect(within(dialog).queryByRole('option')).not.toBeInTheDocument()
        }

        // close the dialog between scenarios
        await user.keyboard('{Escape}')

        {
          rerender(<SubissuesList issue={level3a} />)

          const addButton = screen.getByRole('button', {name: 'Link sub-issue'})
          await user.click(addButton)
          const dialog = screen.getByRole('dialog', {name: 'Select an issue'})

          expect(within(dialog).getByRole('option', {name: level1b.name})).toBeInTheDocument()
        }
      })

      it('should not show nodes that would exceed the maximum breadth of the tree', async () => {
        const parent = createDraftIssue('parent')
        const candidate = createDraftIssue('candidate')

        const children = Array.from({length: 99}, (_, i) => {
          return createDraftIssue(`child-${i + 1}`, {parentTag: parent.tag})
        })

        for (const issue of [parent, candidate, ...children]) {
          mockContentPreviewContext.items.set(issue.id, issue)
          mockContentPreviewContext.versionedItems.set(stripVersionFromId(issue.id), [issue.id])
        }

        const {user, rerender} = render(<SubissuesList issue={parent} />)

        {
          const addButton = screen.getByRole('button', {name: 'Link sub-issue'})
          await user.click(addButton)
          const dialog = screen.getByRole('dialog', {name: 'Select an issue'})

          expect(within(dialog).getByRole('option', {name: candidate.name})).toBeInTheDocument()
        }

        // close the dialog between scenarios
        await user.keyboard('{Escape}')

        // Add another child to the parent, which should get to the maximum breadth
        const extraChild = createDraftIssue('extra-child', {parentTag: parent.tag})
        mockContentPreviewContext.items.set(extraChild.id, extraChild)
        mockContentPreviewContext.versionedItems.set(stripVersionFromId(extraChild.id), [extraChild.id])

        // Force the the tree hook to render by recreating the reference
        // This is a test-specific workaround, in practice the context does this when the items change
        mockContentPreviewContext.items = new Map(mockContentPreviewContext.items)

        {
          rerender(<SubissuesList issue={parent} />)

          const addButton = screen.getByRole('button', {name: 'Link sub-issue'})
          await user.click(addButton)
          const dialog = screen.getByRole('dialog', {name: 'Select an issue'})

          expect(within(dialog).queryByRole('option')).not.toBeInTheDocument()
          // TODO figure out how to test the blankslate; component stays in Loading state
          // expect(within(dialog).getByText('Sub-issue limit reached')).toBeInTheDocument()
        }
      })

      it('should filter the eligible sub-issues based on user input', async () => {
        const epic = createDraftIssue('epic', {name: 'Epic Issue'})
        mockContentPreviewContext.items.set(epic.id, epic)
        mockContentPreviewContext.versionedItems.set(stripVersionFromId(epic.id), [epic.id])

        const eligibleSubIssue1 = createDraftIssue('eligible-1', {name: 'First item'})
        mockContentPreviewContext.items.set(eligibleSubIssue1.id, eligibleSubIssue1)
        mockContentPreviewContext.versionedItems.set(stripVersionFromId(eligibleSubIssue1.id), [eligibleSubIssue1.id])

        const eligibleSubIssue2 = createDraftIssue('eligible-2', {name: 'Second item'})
        mockContentPreviewContext.items.set(eligibleSubIssue2.id, eligibleSubIssue2)
        mockContentPreviewContext.versionedItems.set(stripVersionFromId(eligibleSubIssue2.id), [eligibleSubIssue2.id])

        const {user} = render(<SubissuesList issue={epic} />)

        const addButton = screen.getByRole('button', {name: 'Link sub-issue'})
        expect(addButton).toBeInTheDocument()

        await user.click(addButton)

        const dialog = screen.getByRole('dialog', {name: 'Select an issue'})
        expect(dialog).toBeInTheDocument()

        const filterInput = within(dialog).getByRole('textbox', {name: 'Search'})
        expect(filterInput).toBeInTheDocument()

        await user.type(filterInput, 'First')

        expect(within(dialog).getByRole('option', {name: eligibleSubIssue1.name})).toBeInTheDocument()
        expect(within(dialog).queryByRole('option', {name: eligibleSubIssue2.name})).not.toBeInTheDocument()
      })

      it('should show a blankslate if no issues match the filter', async () => {
        const epic = createDraftIssue('epic', {name: 'Epic Issue'})
        mockContentPreviewContext.items.set(epic.id, epic)
        mockContentPreviewContext.versionedItems.set(stripVersionFromId(epic.id), [epic.id])

        const eligibleSubIssue1 = createDraftIssue('eligible-1', {name: 'First item'})
        mockContentPreviewContext.items.set(eligibleSubIssue1.id, eligibleSubIssue1)
        mockContentPreviewContext.versionedItems.set(stripVersionFromId(eligibleSubIssue1.id), [eligibleSubIssue1.id])

        const eligibleSubIssue2 = createDraftIssue('eligible-2', {name: 'Second item'})
        mockContentPreviewContext.items.set(eligibleSubIssue2.id, eligibleSubIssue2)
        mockContentPreviewContext.versionedItems.set(stripVersionFromId(eligibleSubIssue2.id), [eligibleSubIssue2.id])

        const {user} = render(<SubissuesList issue={epic} />)

        const addButton = screen.getByRole('button', {name: 'Link sub-issue'})
        await user.click(addButton)

        const dialog = screen.getByRole('dialog', {name: 'Select an issue'})
        expect(screen.getAllByRole('option')).toHaveLength(2)

        const filterInput = within(dialog).getByRole('textbox', {name: 'Search'})
        await user.type(filterInput, 'Third')

        expect(within(dialog).queryByRole('option')).not.toBeInTheDocument()
        // TODO figure out how to test the blankslate; component stays in Loading state
        // expect(within(dialog).getByText('No issues found')).toBeInTheDocument()
        // expect(within(dialog).getByText('No issues match your search criteria')).toBeInTheDocument()
      })

      it('should link the selected sub-issue when the option is triggered', async () => {
        const epic = createDraftIssue('epic', {name: 'Epic Issue'})
        mockContentPreviewContext.items.set(epic.id, epic)
        mockContentPreviewContext.versionedItems.set(stripVersionFromId(epic.id), [epic.id])

        const eligibleSubIssue = createDraftIssue('eligible-1', {name: 'Eligible Sub-Issu'})
        mockContentPreviewContext.items.set(eligibleSubIssue.id, eligibleSubIssue)
        mockContentPreviewContext.versionedItems.set(stripVersionFromId(eligibleSubIssue.id), [eligibleSubIssue.id])

        const {user} = render(<SubissuesList issue={epic} />)

        const addButton = screen.getByRole('button', {name: 'Link sub-issue'})
        expect(addButton).toBeInTheDocument()

        await user.click(addButton)

        const dialog = screen.getByRole('dialog', {name: 'Select an issue'})
        const option = within(dialog).getByRole('option', {name: eligibleSubIssue.name})

        await user.click(option)

        expect(mockContentPreviewContext.updateItem).toHaveBeenCalledWith({
          ...eligibleSubIssue,
          parentTag: epic.tag,
          isUserEdited: false,
        })
        expect(mockChatManagerContext.sendChatMessage).toHaveBeenCalledWith(
          expect.objectContaining({
            content: 'Link the sub-issue to its parent issue',
            references: expect.arrayContaining([
              expect.objectContaining({
                type: 'text',
                name: `timeline-event: {"type": "link-sub-issue", "markdownContent": "Linked sub-issue '${eligibleSubIssue.name}'"}`,
              }),
              expect.objectContaining({
                type: 'draft-issue',
                tag: eligibleSubIssue.tag,
                parentTag: epic.tag,
              }),
            ]),
          }),
        )
      })
    })
  })
})
