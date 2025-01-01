import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {CurrentUserProvider} from '@github-ui/current-user'
import {DiffFileTreeAxeRules} from '@github-ui/diff-file-tree/storybook-helper'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {shouldInteractionPlay} from '@github-ui/storybook'
import type {Meta, StoryObj} from '@storybook/react'
import {expect, userEvent, waitFor, within} from '@storybook/test'

import {handlers, payload as defaultPayload, payloadWithSubmoduleDiff} from '../test-utils/storybook/commit-mock-data'
import type {CommitPayload} from '../types/commit-types'
import {Commit} from './Commit'

const StoryWrapper = ({
  children,
  payload,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  enabledFeatures = {},
}: {
  children: React.ReactNode
  payload: CommitPayload
  enabledFeatures?: object
}) => {
  const user = {
    id: 1234,
    login: 'monalisa',
    userEmail: 'monalisa@github.com',
    isStaff: false,
  }

  return (
    // eslint-disable-next-line camelcase
    <Wrapper routePayload={payload} appPayload={{helpUrl: '', enabled_features: enabledFeatures}}>
      <CurrentUserProvider user={user}>
        <CurrentRepositoryProvider repository={payload.repo}>{children}</CurrentRepositoryProvider>
      </CurrentUserProvider>
    </Wrapper>
  )
}

const meta: Meta<typeof Commit> = {
  beforeEach: () => {
    // Erase all stored content in the local storage before each test as comments are stored in local storage
    localStorage.clear()
  },
  title: 'Apps/Commits/Commit',
  component: Commit,
  decorators: [Story => <Story />],
  parameters: {
    a11y: {
      config: {
        rules: DiffFileTreeAxeRules,
      },
    },
  },
} satisfies Meta<typeof Commit>

type Story = StoryObj<typeof Commit>

export const MultipleDiffs: Story = {
  parameters: {
    msw: {
      handlers,
    },
    a11y: {
      config: {
        rules: [
          {
            // Validation errors as ActionBar elements are technically in tab order, visually seen, but are hidden to screen reader users so that it doesn't state out the action bar content when reading out cell.
            id: 'aria-hidden-focus',
            enabled: false,
          },
          ...DiffFileTreeAxeRules,
        ],
      },
    },
  },
  render: () => (
    <StoryWrapper payload={defaultPayload}>
      <Commit />
    </StoryWrapper>
  ),
}

export const MultipleDiffsWithInlineCommentsFeatureEnabled: Story = {
  ...MultipleDiffs,
  parameters: {
    ...MultipleDiffs.parameters,
  },
  render: () => (
    // eslint-disable-next-line camelcase
    <StoryWrapper payload={defaultPayload} enabledFeatures={{diff_inline_comments: true}}>
      <Commit />
    </StoryWrapper>
  ),
}

export const MultipleDiffsWithTabOrderTest: Story = {
  ...MultipleDiffs,
  play: async ({step}) => {
    if (!shouldInteractionPlay()) return

    await step('Assert the correct tab order', async () => {
      await step('Tab to "Browse files" link', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement).toHaveTextContent('Browse files'))
        expect(document.activeElement?.getAttribute('href')).toContain(
          '/monalisa/smile/tree/482ea2f06a4bf6ff40295db68afe2a33d2d9a08b',
        )
      })

      await step('tab to "Author avatar icon" link', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement?.getAttribute('href')).toEqual('/monalisa'))
        expect(document.activeElement?.querySelector('img')).toHaveAttribute(
          'src',
          'http://alambic.github.localhost/avatars/u/2?size=40',
        )
        expect(document.activeElement?.getAttribute('data-hovercard-url')).toEqual('/users/monalisa/hovercard')
      })

      await step('Tab to "Author commits" link', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement).toHaveTextContent('monalisa'))
        expect(document.activeElement?.getAttribute('href')).toContain('/monalisa/smile/commits?author=monalisa')
        expect(document.activeElement?.ariaLabel).toEqual('commits by monalisa')
      })

      await step('Tab to "Parent commit" link', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement).toHaveTextContent('89c5109'))
        expect(document.activeElement?.getAttribute('href')).toContain(
          '/monalisa/smile/commit/89c5109b75b889f2842d5692b8f3a260854e591d',
        )
      })

      await step('Tab to "Copy full sha for {commit sha}" button', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement).toHaveAccessibleName('Copy full SHA for 482ea2f'))
        expect(document.activeElement?.nodeName).toEqual('BUTTON')
      })

      await step('Tab to "Filter files..." input', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement?.ariaLabel).toEqual('Filter files…'))
        expect(document.activeElement?.nodeName).toEqual('INPUT')
      })

      await step('Tab to "Filter" button', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement?.ariaLabel).toEqual('Filter'))
        expect(document.activeElement?.nodeName).toEqual('BUTTON')
      })

      await step('Tab to "First file/folder in the tree view list" (e.g. "app" folder for this test)', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement).toHaveTextContent('app'))
        expect(document.activeElement?.nodeName).toEqual('LI')
      })

      await step('Tab to "Splitter pane bar" seperating the File Tree and Diffs list', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement?.ariaLabel).toEqual('Draggable pane splitter'))
      })

      await step('Tab to "Collapse file tree" button', async () => {
        await userEvent.tab()
        // Currently using a tooltip to display the button's label, which means the button's parent element has aria-label content
        await waitFor(() => expect(document.activeElement?.parentElement?.ariaLabel).toEqual('Collapse file tree'))
        expect(document.activeElement?.nodeName).toEqual('BUTTON')
      })

      await step('Tab to "Up" button (e.g. go to top of the page)', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement).toHaveTextContent('Top'))
        expect(document.activeElement?.nodeName).toEqual('BUTTON')
      })

      await step('Tab to "Search within code" input', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement?.ariaLabel).toEqual('Search within code'))
        expect(document.activeElement?.nodeName).toEqual('INPUT')
      })

      await step('Tab to "Open diff view settings" button', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement?.ariaLabel).toEqual('Open diff view settings'))
        expect(document.activeElement?.nodeName).toEqual('BUTTON')
      })

      await step('Tab to the diff list\'s first file header "Collapse file: {filename}" button', async () => {
        await userEvent.tab()
        await waitFor(() =>
          expect(document.activeElement?.ariaLabel).toEqual(
            'collapse file: app/components/pull_requests/file_tree/root_component.rb',
          ),
        )
        expect(document.activeElement?.nodeName).toEqual('BUTTON')
      })

      await step('Tab to "diff file path" link', async () => {
        await userEvent.tab()
        await waitFor(() =>
          expect(document.activeElement?.getAttribute('href')).toEqual(
            '#diff-b380a745f19cffd4e405d0b2fbac10a2245703d66a901df274d0a41cb1b6839b',
          ),
        )
        expect(document.activeElement).toHaveTextContent('app/components/pull_requests/file_tree/root_component.rb')
      })

      await step('Tab to "Copy file name to clipboard" icon button', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement).toHaveAccessibleName('Copy file name to clipboard'))
        expect(document.activeElement?.nodeName).toEqual('BUTTON')
      })

      await step('Tab to "Expand all lines: {filepath}" icon button', async () => {
        await userEvent.tab()
        await waitFor(() =>
          expect(document.activeElement?.ariaLabel).toEqual(
            'expand all lines: app/components/pull_requests/file_tree/root_component.rb',
          ),
        )
        expect(document.activeElement?.getAttribute('data-file-path')).toEqual(
          'app/components/pull_requests/file_tree/root_component.rb',
        )
        expect(document.activeElement?.nodeName).toEqual('BUTTON')
      })

      await step('Tab to "More options" icon button', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement?.ariaLabel).toEqual('More options'))
        expect(document.activeElement?.nodeName).toEqual('BUTTON')
      })

      await step('Tab to the "first table cell" in the diff table grid (e.g. Hunk header)', async () => {
        await userEvent.tab()
        await waitFor(() =>
          expect(document.activeElement).toHaveTextContent(
            '@@ -22,7 +22,7 @@ class RootComponent < ApplicationComponent',
          ),
        )
        expect(document.activeElement?.nodeName).toEqual('TD')
      })

      await step('Tab to the "Expand file up from line {linenumber}" icon button', async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement?.ariaLabel).toEqual('Expand file up from line 22'))
        expect(document.activeElement?.nodeName).toEqual('BUTTON')
      })

      await step('Tab to the diff list\'s second file header "Collapse file: {filename}" button', async () => {
        await userEvent.tab()
        await waitFor(() =>
          expect(document.activeElement?.ariaLabel).toEqual('collapse file: app/helpers/react_helper.rb'),
        )
        expect(document.activeElement?.nodeName).toEqual('BUTTON')
      })
    })
  },
}

export const ReplyingToThread: Story = {
  ...MultipleDiffs,
  parameters: {
    msw: {
      handlers,
    },
    a11y: {
      config: {
        rules: DiffFileTreeAxeRules,
      },
    },
  },
  render: () => (
    // eslint-disable-next-line camelcase
    <StoryWrapper payload={defaultPayload} enabledFeatures={{diff_inline_comments: true}}>
      <Commit />
    </StoryWrapper>
  ),
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)
    let codeCell: HTMLElement

    await step('Click code cell with active comment thread', async () => {
      codeCell = await canvas.findByRole('gridcell', {
        name: '- enabled_flags: T.nilable(T::Array[T.untyped]), # Array passing app specific flags to the client side, needed to do more than basic ff checks aka per user or globally',
      })
      await userEvent.click(codeCell)
    })

    await step('Enter focus mode and tab to the reply input', async () => {
      await userEvent.keyboard('{Enter}')
      await waitFor(() => expect(codeCell.role).toEqual('dialog'))

      // Tab until active element is "Write a reply" button
      while (document.activeElement?.textContent !== 'Write a reply') {
        await userEvent.tab()
      }

      expect(document.activeElement).toHaveTextContent('Write a reply')
    })

    await step('Enter text into the reply input and submit the reply', async () => {
      await userEvent.keyboard(`{enter}`)
      await waitFor(() => expect(document.activeElement!.getAttribute('placeholder')).toEqual('Leave a comment'))
      await userEvent.keyboard('This code is no longer needed.')

      // Tab until active element is "Reply" button
      while (document.activeElement?.textContent !== 'Reply') {
        await userEvent.tab()
      }

      await waitFor(() => expect(document.activeElement).toHaveTextContent('Reply'))

      await userEvent.keyboard(`{enter}`)
    })

    await step('Assert the reply was submitted and new comment is rendered in the thread', async () => {
      await waitFor(() => expect(within(codeCell).queryByRole('button', {name: 'Reply'})).not.toBeInTheDocument())

      await waitFor(() => expect(within(codeCell).getByText('This code is no longer needed.')).toBeInTheDocument())
    })
  },
}

export const SubmoduleDiff: Story = {
  parameters: {
    msw: {
      handlers,
    },
    a11y: {
      config: {
        rules: [
          {
            // Validation errors as ActionBar elements are technically in tab order, visually seen, but are hidden to screen reader users so that it doesn't state out the action bar content when reading out cell.
            id: 'aria-hidden-focus',
            enabled: false,
          },
          ...DiffFileTreeAxeRules,
        ],
      },
    },
  },
  render: () => (
    <StoryWrapper payload={payloadWithSubmoduleDiff}>
      <Commit />
    </StoryWrapper>
  ),
}

export const UserMakingSingleLineSelectionsTest: Story = {
  ...MultipleDiffs,
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Clicking a line number cell selects all table cells contained within that line', async () => {
      const lineNumberCells = await canvas.findAllByRole('gridcell', {
        name: '22',
      })
      expect(lineNumberCells).toHaveLength(2)

      const firstSelectedTableCells = Array.from(
        lineNumberCells[0]!.closest('tr')!.querySelectorAll('td[role="gridcell"]'),
      )

      for (const cell of firstSelectedTableCells) {
        expect(cell.getAttribute('data-selected')).toEqual('false')
      }

      await userEvent.click(lineNumberCells[0]!)

      for (const cell of firstSelectedTableCells) {
        await waitFor(() => expect(cell.getAttribute('data-selected')).toEqual('true'))
      }
    })

    await step(
      'Clicking a line number cell in a different diff removes previous line selection and sets new line selection',
      async () => {
        const nextDiffLineNumberCells = await canvas.findAllByRole('gridcell', {
          name: '66',
        })

        const tableCells = nextDiffLineNumberCells[0]!.closest('tr')!.querySelectorAll('td[role="gridcell"]')

        for (const cell of tableCells) {
          expect(cell.getAttribute('data-selected')).toEqual('false')
        }

        await userEvent.click(nextDiffLineNumberCells[0]!)

        for (const cell of tableCells) {
          await waitFor(() => expect(cell.getAttribute('data-selected')).toEqual('true'))
        }

        const previouslySelectedDiffLineNumberCells = await canvas.findAllByRole('gridcell', {
          name: '22',
        })

        expect(previouslySelectedDiffLineNumberCells).toHaveLength(2)

        const previouslySelectedDiffTableCells = Array.from(
          previouslySelectedDiffLineNumberCells[0]!.closest('tr')!.querySelectorAll('td[role="gridcell"]'),
        )

        for (const cell of previouslySelectedDiffTableCells) {
          await waitFor(() => expect(cell.getAttribute('data-selected')).toEqual('false'))
        }
      },
    )
  },
}

export const SelectingMultipleLinesWithMouseDragTest: Story = {
  ...MultipleDiffs,
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    let firstLineNumberCell: HTMLElement
    let secondLineNumberCell: HTMLElement

    await step(
      'Click starting line number cell and drag down to the line number cell on the next diff line row',
      async () => {
        firstLineNumberCell = (
          await canvas.findAllByRole('gridcell', {
            name: '22',
          })
        )[0]!
        secondLineNumberCell = (
          await canvas.findAllByRole('gridcell', {
            name: '24',
          })
        )[0]!

        expect(firstLineNumberCell.getAttribute('data-selected')).toEqual('false')
        expect(secondLineNumberCell.getAttribute('data-selected')).toEqual('false')

        // Click on the first line number cell and mouse drag to the second line number cell
        await userEvent.pointer([
          // touch the screen at first cell
          {keys: '[MouseLeft>]', target: firstLineNumberCell},
          // move the touch pointer to end cell
          {target: secondLineNumberCell},
          // release the touch pointer at end cell position
          {keys: '[/MouseLeft]'},
        ])

        expect(firstLineNumberCell.getAttribute('data-selected')).toEqual('true')
        expect(secondLineNumberCell.getAttribute('data-selected')).toEqual('true')
      },
    )

    await step('Clicking a different line number cell will deselect the multi-line selection', async () => {
      const newLineNumberCell = (
        await canvas.findAllByRole('gridcell', {
          name: '27',
        })
      )[0]!

      await userEvent.click(newLineNumberCell)

      expect(newLineNumberCell.getAttribute('data-selected')).toEqual('true')
      expect(firstLineNumberCell.getAttribute('data-selected')).toEqual('false')
      expect(secondLineNumberCell.getAttribute('data-selected')).toEqual('false')
    })
  },
}

export default meta
