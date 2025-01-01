import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'
import {noop} from '@github-ui/noop'
import {DiffFileTreeAxeRules} from '@github-ui/diff-file-tree/storybook-helper'
import {shouldInteractionPlay} from '@github-ui/storybook'
import {expect, userEvent, waitFor, within} from '@storybook/test'
import {DiffLines, type DiffLinesProps} from './DiffLines'
import {mockDefaultDiffLines, mockDiffEntryData, mockReactHelperDiffEntryData} from '../test-utils/mock-data'

const meta = {
  title: 'Diff Lines/Selected Diff Lines',
  component: DiffLines,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof DiffLines>

export default meta

const defaultArgs: Omit<DiffLinesProps, 'diffEntryData'> = {
  baseHelpUrl: 'https://help.github.com',
  diffLinesManuallyUnhidden: false,
  onHandleLoadDiff: noop,
  addInjectedContextLines: noop,
  commentBatchPending: false,
  commentingEnabled: false,
  repositoryId: '',
  subjectId: '',
  subject: {
    isInMergeQueue: false,
    state: 'OPEN',
  },
  viewerData: {
    avatarUrl: 'https://avatars.githubusercontent.com/u/1',
    diffViewPreference: 'unified',
    isSiteAdmin: false,
    lineSpacingPreference: 'compact',
    commentsPreference: 'visible',
    login: 'monalisa',
    tabSizePreference: 8,
    viewerCanComment: true,
    viewerCanApplySuggestion: false,
  },
}

const defaultDiffEntryArgs: DiffLinesProps = {
  ...defaultArgs,
  diffEntryData: mockDiffEntryData,
}

const reactHelperDiffEntryArgs: DiffLinesProps = {
  ...defaultArgs,
  diffEntryData: mockReactHelperDiffEntryData,
}

type Story = StoryObj<typeof DiffLines>

const Default: Story = {
  parameters: {
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
    <Wrapper>
      <DiffLines {...defaultDiffEntryArgs} />
    </Wrapper>
  ),
}

const MultipleDiffs: Story = {
  parameters: {
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
    <Wrapper>
      <DiffLines {...defaultDiffEntryArgs} />
      <br />
      <DiffLines {...reactHelperDiffEntryArgs} />
    </Wrapper>
  ),
}

const WithHiddenUnicode: Story = {
  parameters: {
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
    <Wrapper>
      <DiffLines
        {...defaultDiffEntryArgs}
        diffEntryData={{
          ...defaultDiffEntryArgs.diffEntryData,
          diffLines: mockDefaultDiffLines.map(diffLine => ({
            ...diffLine,
            text: `\u202E${diffLine.text}`,
            html: `\u202E${diffLine.html}`,
          })),
        }}
      />
    </Wrapper>
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
  ...Default,
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

export const SelectingMultipleLinesWithKeyboardTest: Story = {
  ...Default,
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    let firstLineNumberCell: HTMLElement
    let secondLineNumberCell: HTMLElement
    let firstDiffContentCell: HTMLElement

    await step('Use keyboard to select multiple diff lines', async () => {
      firstLineNumberCell = (
        await canvas.findAllByRole('gridcell', {
          name: '23',
        })
      )[0]!
      secondLineNumberCell = (
        await canvas.findAllByRole('gridcell', {
          name: '24',
        })
      )[0]!
      firstDiffContentCell = (
        await canvas.findAllByRole('gridcell', {
          name: '# The parent component for a file tree, which builds a tree representation',
        })
      )[0]!

      // select the diff content next to the first cell
      // then keyboard nav to the adjacent line number to clear any previous selection
      // this lets us start keyboard navigation with a clean slate
      await userEvent.click(firstDiffContentCell)
      await userEvent.keyboard('{ArrowLeft}')

      // validate we haven't selected any lines yet
      expect(firstLineNumberCell.getAttribute('data-selected')).toEqual('false')
      expect(secondLineNumberCell.getAttribute('data-selected')).toEqual('false')
    })

    await step('Shift + ArrowDown to select the next line', async () => {
      await userEvent.keyboard('{Shift>}{ArrowDown}{/Shift}')

      expect(firstLineNumberCell.getAttribute('data-selected')).toEqual('true')
      expect(secondLineNumberCell.getAttribute('data-selected')).toEqual('true')
    })

    await step('Keyboard nav to a different cell will deselect the multi-line selection', async () => {
      await userEvent.keyboard('{ArrowDown}')

      expect(firstLineNumberCell.getAttribute('data-selected')).toEqual('false')
      expect(secondLineNumberCell.getAttribute('data-selected')).toEqual('false')
    })
  },
}

export const ShowsHiddenUnicodeBanner: Story = {
  ...WithHiddenUnicode,
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Hidden Unicode Banner is shown', async () => {
      const hiddenUnicodeBanner = await canvas.findByRole('button', {
        name: 'Show hidden characters',
      })

      expect(hiddenUnicodeBanner).toBeVisible()
    })

    await step('Clicking the button reveals hidden unicode characters', async () => {
      const hiddenUnicodeBanner = await canvas.findByRole('button', {
        name: 'Show hidden characters',
      })

      await userEvent.click(hiddenUnicodeBanner)

      const diffLines = canvas.queryAllByText(/[\u202E]/)

      expect(diffLines).toHaveLength(0)

      const hiddenUnicodeReplacements = canvas.queryAllByText(/U\+202E/)
      expect(hiddenUnicodeReplacements).toHaveLength(mockDefaultDiffLines.length)
    })

    await step('Clicking the button again hides hidden unicode characters', async () => {
      const hiddenUnicodeBanner = await canvas.findByRole('button', {
        name: 'Hide revealed characters',
      })

      await userEvent.click(hiddenUnicodeBanner)

      const diffLines = canvas.queryAllByText(/[\u202E]/)

      expect(diffLines).toHaveLength(mockDefaultDiffLines.length)

      const hiddenUnicodeReplacements = canvas.queryAllByText(/U\+202E/)
      expect(hiddenUnicodeReplacements).toHaveLength(0)
    })
  },
}
