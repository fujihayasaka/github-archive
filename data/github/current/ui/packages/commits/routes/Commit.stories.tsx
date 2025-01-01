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
  tags: ['flaky'],
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
        await waitFor(() => expect(document.activeElement).toHaveAccessibleName('Filter options'))
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
            'Collapse file: app/components/pull_requests/file_tree/root_component.rb',
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
            'Expand all lines: app/components/pull_requests/file_tree/root_component.rb',
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
          expect(document.activeElement?.ariaLabel).toEqual('Collapse file: app/helpers/react_helper.rb'),
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
    <StoryWrapper payload={defaultPayload}>
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

export const AddConversationWithMouseAndKeyboardTest: Story = {
  ...MultipleDiffs,
  parameters: {
    msw: {
      handlers,
    },
    a11y: {
      element: '#storybook-root',
      config: {
        rules: [
          ...DiffFileTreeAxeRules,
          {
            id: 'landmark-no-duplicate-banner',
            enabled: false,
          },
          {
            id: 'landmark-unique',
            enabled: false,
          },
        ],
      },
    },
  },
  render: () => (
    <StoryWrapper payload={defaultPayload}>
      <Commit />
    </StoryWrapper>
  ),
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)
    let codeCell: HTMLElement

    await step('Hover over code cell without an active comment thread', async () => {
      codeCell = await canvas.findByRole('gridcell', {
        name: '- enabled_flags: [],',
      })
      await userEvent.hover(codeCell)
    })

    await step('Enter in gridcell will activate "Leave a comment" with active Write tab', async () => {
      await waitFor(() => expect(codeCell.role).toEqual('gridcell'))
      await userEvent.click(codeCell)
      await userEvent.keyboard('{Enter}')

      const writeButton = await canvas.findByRole('tab', {
        name: 'Write',
      })
      await waitFor(() => {
        expect(writeButton).toBeInTheDocument()
        expect(canvas.queryByPlaceholderText('Leave a comment')).toBeInTheDocument()
      })

      await userEvent.click(within(codeCell).getByRole('button', {name: 'Cancel'}))
    })

    await step(
      'Tab to "Add comment" icon button and press enter activate "Leave a comment" input box and "focus" mode',
      async () => {
        await userEvent.click(within(codeCell).getByLabelText('Add comment'))
        await waitFor(() => expect(codeCell.role).toEqual('dialog'))
        expect(within(codeCell).getByRole('button', {name: 'Return to code'})).toBeInTheDocument()
        await waitFor(() => expect(document.activeElement?.getAttribute('placeholder')).toEqual('Leave a comment'))
        expect(within(codeCell).queryByLabelText('Add comment')).not.toBeInTheDocument()
      },
    )

    await step('Enter text into the reply input and submit the reply', async () => {
      await waitFor(() => expect(document.activeElement!.getAttribute('placeholder')).toEqual('Leave a comment'))
      await userEvent.keyboard('This is a comment made with mouse and keyboard.')
      await userEvent.click(within(codeCell).getByRole('button', {name: 'Comment'}))
      await waitFor(() => expect(canvas.queryByPlaceholderText('Leave a comment')).not.toBeInTheDocument())
    })

    await step('The code cell is still in focus mode and new comment is visible', async () => {
      expect(codeCell.role).toEqual('dialog')
      // TODO: When created comments are appended to InlineMarkers,
      // assert new comment is rendered as the first comment in a thread for the diff line
      // expect(within(codeCell).getByText('This is a comment made with mouse and keyboard.')).toBeInTheDocument()
      // assert that the "Exit" button is still in the document
      // expect(within(codeCell).getByRole('button', {name: 'Exit'})).toBeInTheDocument()
    })

    await step('Click code cell without an active comment thread', async () => {
      codeCell = await canvas.findByRole('gridcell', {
        name: '+ # each child is a PullRequests::FileTree::NodeComponent.',
      })
      await userEvent.click(codeCell)
    })

    await step(
      'Tab to "Add comment" icon button and press enter to activate "Leave a comment" input box and "focus" mode',
      async () => {
        await userEvent.tab()
        await waitFor(() => expect(document.activeElement?.ariaLabel).toEqual('Add comment'))
        await userEvent.keyboard('{Enter}')
        await waitFor(() => expect(codeCell.role).toEqual('dialog'))
        expect(within(codeCell).getByRole('button', {name: 'Return to code'})).toBeInTheDocument()
        await waitFor(() => expect(document.activeElement?.getAttribute('placeholder')).toEqual('Leave a comment'))
        expect(within(codeCell).queryByLabelText('Add comment')).not.toBeInTheDocument()
      },
    )

    await step('Enter text into the reply input and submit the reply', async () => {
      await waitFor(() => expect(document.activeElement!.getAttribute('placeholder')).toEqual('Leave a comment'))
      await userEvent.keyboard('This is a comment made with just a keyboard.')
      await userEvent.keyboard('{Meta>}{enter}{/Meta}')
      await waitFor(() => expect(canvas.queryByPlaceholderText('Leave a comment')).not.toBeInTheDocument())
    })

    await step('The code cell is still in focus mode and new comment is visible', async () => {
      expect(codeCell.role).toEqual('gridcell')
      // TODO: When created comments are appended to InlineMarkers,
      // assert new comment is rendered as the first comment in a thread for the diff line
      // expect(within(codeCell).getByText('This is a comment made with just a keyboard.')).toBeInTheDocument()
      // assert that the "Exit" button is still in the document
      // expect(within(codeCell).getByRole('button', {name: 'Exit'})).toBeInTheDocument()
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

export const CopyDiff: Story = {
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
    <StoryWrapper payload={defaultPayload}>
      <Commit />
    </StoryWrapper>
  ),
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)
    let codeCell: HTMLElement

    await step('Unified view: copies single selection via content cell click', async () => {
      codeCell = await canvas.findByRole('gridcell', {
        name: '- enabled_flags: T.nilable(T::Array[T.untyped]), # Array passing app specific flags to the client side, needed to do more than basic ff checks aka per user or globally',
      })
      await userEvent.click(codeCell)
      expect(document.activeElement).toBe(codeCell)
      await userEvent.keyboard('{Meta>}{c}')
      // FIX ME: This is not working as expected. https://github.com/github/pull-requests/issues/17495
      // await expect(await navigator.clipboard.readText()).toEqual(
      //   '- enabled_flags: T.nilable(T::Array[T.untyped]), # Array passing app specific flags to the client side, needed to do more than basic ff checks aka per user or globally',
      // )
    })

    await step('Unified view: copies single selection via number cell click', async () => {
      const numberCells = canvas.getAllByRole('gridcell', {name: '65'})

      await userEvent.click(numberCells[0] as HTMLElement)
      expect(document.activeElement).toBe(numberCells[0])

      await userEvent.keyboard('{Meta>}{c}')
      await expect(await navigator.clipboard.readText()).toEqual(
        'run_async_with_defer: T::Boolean, # Boolean defaulting to false signaling if the app should be rendered with the defer directive.',
      )
    })
  },
}
export default meta
