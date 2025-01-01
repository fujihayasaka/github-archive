// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import type {Meta, StoryObj} from '@storybook/react'
import {expect, userEvent, waitFor, within} from '@storybook/test'

import {Filter} from '../../Filter'
import {handlers} from '../../mocks/handlers'
import {AssigneeFilterProvider, IsFilterProvider, MilestoneFilterProvider, StateFilterProvider} from '../../providers'
import {ProviderSupportStatus} from '../../types'
import {getActiveSuggestion, getSuggestions} from '../utils/interaction-test-helpers'
import {setupMockFilterProviders} from '../utils/mock-providers'

type Story = StoryObj<typeof Filter>

const meta = {
  title: 'Recipes/Filter/Interactions/Suggestions',
  component: Filter,
  parameters: {
    msw: {
      handlers,
    },
  },
  tags: ['flaky'],
  args: {
    id: 'filter-sb',
    context: {repo: 'github/github'},
    label: 'Filter suggestions',
    providers: setupMockFilterProviders(),
    settings: {aliasMatching: false, groupAndKeywordSupport: true},
  },
} satisfies Meta<typeof Filter>
export default meta

export const ShowSuggestions: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    input.click()

    await userEvent.type(input, 'author:')

    await waitFor(() => {
      canvas.getByRole('option', {name: /Signed-in user/i}).click()
    })
    await expect(input).toHaveValue('author:@me')
  },
}

export const AriaActiveDescendantOnExpectedItem: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.type(input, 's')
    await expect(input).not.toHaveAttribute('aria-activedescendant')
    await userEvent.keyboard('{ArrowDown}')
    await expect(input).toHaveAttribute('aria-activedescendant', 'suggestion-0')
  },
}

export const NavigatesAndSelectsSuggestionUsingArrowKeys: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await userEvent.type(input, 'sta')
    await expect(getActiveSuggestion(canvas)).toBeUndefined()
    await waitFor(() => expect(getSuggestions(canvas)).toEqual(['State', 'Status']))

    await userEvent.keyboard('{ArrowDown}')
    await expect(getActiveSuggestion(canvas)).toHaveTextContent(/State/i)
    await userEvent.keyboard('{ArrowDown}')
    await expect(getActiveSuggestion(canvas)).toHaveTextContent(/Status/i)
    await userEvent.keyboard('{ArrowDown}')
    // Arrow down at the end clears the active suggestion
    await expect(getActiveSuggestion(canvas)).toBeUndefined()

    await userEvent.keyboard('{ArrowUp}')
    await expect(getActiveSuggestion(canvas)).toHaveTextContent(/Status/i)
    await userEvent.keyboard('{ArrowUp}')
    await expect(getActiveSuggestion(canvas)).toHaveTextContent(/State/i)
    await userEvent.keyboard('{ArrowUp}')
    // Arrow up at the end clears the active suggestion
    await expect(getActiveSuggestion(canvas)).toBeUndefined()
    // Arrow up at the top cycles to the bottom
    await userEvent.keyboard('{ArrowUp}')
    await expect(getActiveSuggestion(canvas)).toHaveTextContent(/Status/i)

    await userEvent.keyboard('{Enter}')
    await expect(input).toHaveValue('status:')
  },
}

export const FiltersByPriority: Story = {
  args: {
    ...meta.args,
    providers: [
      new StateFilterProvider('mixed', {
        priority: 10, // default is 3
      }),
      new MilestoneFilterProvider({
        priority: 3, // default is 10
      }),
    ],
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    await userEvent.type(canvas.getByRole('combobox'), ' ')

    await expect(getSuggestions(canvas)).toEqual(['Milestone', 'AND', 'OR', 'Exclude'])
  },
}

export const IncludeSuggestions: Story = {
  args: {
    ...meta.args,
    providers: [
      new StateFilterProvider('mixed', {
        support: {status: ProviderSupportStatus.Supported},
        filterTypes: {
          inclusive: true,
          exclusive: true,
          valueless: false,
          multiKey: false,
          multiValue: true,
        },
      }),
    ],
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    await userEvent.type(canvas.getByRole('combobox'), 'sta')

    await expect(getSuggestions(canvas)).toEqual(['State'])
  },
}

export const ExcludeSuggestions: Story = {
  args: {
    ...meta.args,
    providers: [
      new StateFilterProvider('mixed', {
        support: {status: ProviderSupportStatus.Supported},
        filterTypes: {
          inclusive: true,
          exclusive: true,
          valueless: false,
          multiKey: false,
          multiValue: true,
        },
      }),
    ],
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    await userEvent.type(canvas.getByRole('combobox'), '-sta')

    await expect(canvas.findByTestId('suggestions-heading')).resolves.toHaveTextContent('Exclude')

    await expect(getSuggestions(canvas)).toEqual(['State'])
  },
}

export const LegacyStateIsFilterWithMixedState: Story = {
  args: {
    ...meta.args,
    providers: [
      new IsFilterProvider(['issue', 'pr', 'open', 'closed', 'draft', 'merged']),
      new StateFilterProvider('mixed', {}),
    ],
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    await userEvent.type(canvas.getByRole('combobox'), ' ')

    await expect(getSuggestions(canvas)).toEqual(['Is', 'State', 'AND', 'OR', 'Exclude'])

    canvas.getByRole('option', {name: /Is/i}).click()

    await waitFor(() => {
      void expect(getSuggestions(canvas)).toEqual([
        'Exclude is',
        'Issue',
        'Pull Request',
        'Open',
        'Closed',
        'Draft',
        'Merged',
      ])
    })
  },
}

export const AssigneeFilterWithWildcardSuggestion: Story = {
  args: {
    ...meta.args,
    providers: [
      new AssigneeFilterProvider({
        currentUserLogin: 'monalisa',
        currentUserAvatarUrl: 'https://avatars.githubusercontent.com/u/90914?v=4',
        showHasValue: true,
        showAtMe: true,
      }),
    ],
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    await userEvent.type(canvas.getByRole('combobox'), ' ')

    await expect(getSuggestions(canvas)).toEqual(['Assignee', 'AND', 'OR', 'Exclude'])

    canvas.getByRole('option', {name: /Assignee/i}).click()

    await waitFor(() => {
      void expect(getSuggestions(canvas)).toContain('Has assignee')
    })
  },
}

export const ExcludeSuggestionsWithFilters: Story = {
  args: {
    ...meta.args,
    providers: [
      new IsFilterProvider(['issue', 'pr', 'open', 'closed', 'draft', 'merged']),
      new StateFilterProvider('mixed', {
        support: {status: ProviderSupportStatus.Supported},
        filterTypes: {
          inclusive: true,
          exclusive: true, // to make sure we are only rendering providers that are exclusive
          valueless: false,
          multiKey: false,
          multiValue: true,
        },
      }),
    ],
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    await userEvent.type(canvas.getByRole('combobox'), '-')

    await expect(getSuggestions(canvas)).toEqual(['Is', 'State'])
    await expect(canvas.findByTestId('suggestions-heading')).resolves.toHaveTextContent('Exclude')
  },
}

export const ExcludeSuggestionsIfProvidersExistSupportingExclusion: Story = {
  args: {
    ...meta.args,
    providers: [
      new IsFilterProvider(['issue', 'pr', 'open', 'closed', 'draft', 'merged']),
      new StateFilterProvider('mixed', {
        support: {status: ProviderSupportStatus.Supported},
        filterTypes: {
          inclusive: true,
          exclusive: true,
          valueless: false,
          multiKey: false,
          multiValue: true,
        },
      }),
    ],
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.type(input, ' ')

    await expect(getSuggestions(canvas)).toEqual(['Is', 'State', 'AND', 'OR', 'Exclude'])

    canvas.getByRole('option', {name: /Exclude/i}).click()

    await waitFor(() => {
      void expect(getSuggestions(canvas)).toEqual(['Is', 'State'])
    })

    canvas.getByRole('option', {name: /State/i}).click()

    await waitFor(() => {
      void expect(input).toHaveValue(' -state:')
    })
  },
}

export const ExcludeModifierForFilterProviderCreatedWithPartialOptionsList: Story = {
  args: {
    ...meta.args,
    providers: [
      new IsFilterProvider(['issue', 'pr', 'open', 'closed', 'draft', 'merged'], {filterTypes: {exclusive: true}}),
    ],
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.type(input, ' ')

    await waitFor(() => expect(getSuggestions(canvas)).toEqual(['Is', 'AND', 'OR', 'Exclude']))

    await waitFor(() => canvas.getByRole('option', {name: /Exclude/i}).click())
    await expect(input).toHaveValue(' -')

    await userEvent.keyboard('{ArrowDown}')
    await userEvent.keyboard('{Enter}')
    await waitFor(() => expect(input).toHaveValue(' -is:'))
  },
}

export const InsertExcludeKeyModifierWhenSelectingExcludeSuggestion: Story = {
  args: {
    ...meta.args,
    providers: [
      new IsFilterProvider(['issue', 'pr', 'open', 'closed', 'draft', 'merged']),
      new StateFilterProvider('mixed', {
        support: {status: ProviderSupportStatus.Supported},
        filterTypes: {
          inclusive: true,
          exclusive: true,
          valueless: false,
          multiKey: false,
          multiValue: true,
        },
      }),
    ],
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.type(input, ' ')

    await waitFor(() => expect(getSuggestions(canvas)).toEqual(['Is', 'State', 'AND', 'OR', 'Exclude']))

    await waitFor(() => canvas.getByRole('option', {name: /Exclude/i}).click())
    await expect(input).toHaveValue(' -')
  },
}

export const InsertExcludeKeySuggestionWithPartialMatchesBeginningWithADash: Story = {
  args: {
    ...meta.args,
    providers: [
      new IsFilterProvider(['issue', 'pr', 'open', 'closed', 'draft', 'merged']),
      new StateFilterProvider('mixed', {
        support: {status: ProviderSupportStatus.Supported},
        filterTypes: {
          inclusive: true,
          exclusive: true,
          valueless: false,
          multiKey: false,
          multiValue: true,
        },
      }),
    ],
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const input = canvas.getByRole('combobox')

    await userEvent.type(input, '-sta')
    await expect(canvas.findByTestId('suggestions-heading')).resolves.toHaveTextContent('Exclude')

    await waitFor(() => expect(getSuggestions(canvas)).toEqual(['State']))

    await waitFor(() => canvas.getByRole('option', {name: /state/i}).click())
    await expect(input).toHaveValue('-state:')
  },
}

export const ClosesSuggestionsListWhenEscapePressed: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await userEvent.type(input, 's')
    await expect(input).toHaveAttribute('aria-expanded', 'true')
    await userEvent.keyboard('{Escape}')
    await expect(input).toHaveAttribute('aria-expanded', 'false')
  },
}

export const ShowSuggestionsWhenSpaceCharacterPressed: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await userEvent.type(input, 's')
    await userEvent.keyboard('{ArrowDown}')
    await userEvent.keyboard('{Enter}')
    await expect(input).toHaveValue('state:')

    await userEvent.keyboard('{ArrowDown}')
    await userEvent.keyboard('{Enter}')
    await expect(input).toHaveValue('state:open')

    await userEvent.keyboard(' ')
    await expect(input).toHaveAttribute('aria-expanded', 'true')
    await userEvent.keyboard('{Backspace}')
    await expect(input).toHaveAttribute('aria-expanded', 'false')

    // Some languages, such as Japanese, have a full-width space as opposed to the English half-space character
    await userEvent.keyboard('　')
    await expect(input).toHaveAttribute('aria-expanded', 'true')
  },
}

export const ShowsSuggestionsWhenInputFocusedWithNoValue: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await userEvent.click(input)
    await expect(input).toHaveFocus()
    await expect(input).toHaveAttribute('aria-expanded', 'true')
  },
}

export const DoesNotShowSuggestionsWhenInputFocusedWithPrePopulatedValue: Story = {
  args: {
    ...meta.args,
    filterValue: 'state:open',
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await userEvent.click(input)
    await expect(input).toHaveFocus()
    await expect(input).toHaveAttribute('aria-expanded', 'false')
  },
}

export const ShowSuggestionsAfterOpeningParenthesisTyped: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await userEvent.type(input, '(')
    await expect(input).toHaveAttribute('aria-expanded', 'true')
    await expect(canvas.getByRole('listbox', {name: 'Suggestions'})).toBeInTheDocument()
  },
}

export const DoesNotShowSuggestionsIfOpeningParenthesisTypedInQuotedValue: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await userEvent.type(input, 'state:"open (')
    await expect(canvas.queryByRole('listbox', {name: 'Suggestions'})).not.toBeInTheDocument()
    await expect(input).toHaveAttribute('aria-expanded', 'false')
  },
}

export const ShowSuggestionsIfOpenParenTypedInsideNestedGroup: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await userEvent.type(input, 'state:open AND (no:status AND )')
    await userEvent.keyboard('{ArrowLeft}(')

    await expect(input).toHaveAttribute('aria-expanded', 'true')
    await expect(canvas.getByRole('listbox', {name: 'Suggestions'})).toBeInTheDocument()
  },
}

export const InsertsSuggestionInBetweenParens: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await userEvent.type(input, '(')
    await expect(input).toHaveAttribute('aria-expanded', 'true')
    await expect(canvas.getByRole('listbox', {name: 'Suggestions'})).toBeInTheDocument()

    await waitFor(() => canvas.getByRole('option', {name: /label/i}).click())
    await expect(input).toHaveValue('(label:)')
  },
}

export const InsertSuggestionForValueWhenEmptyQuotes: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await userEvent.type(input, 'state:"')

    await expect(input).toHaveValue('state:""')

    await waitFor(() => canvas.getByRole('option', {name: /Closed/i}).click())
    await expect(input).toHaveValue('state:closed')
  },
}

export const InsertSuggestionForValueWhenInQuotes: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await userEvent.type(input, 'label:triage,"a1 ')

    await expect(input).toHaveValue('label:triage,"a1 "')

    await waitFor(() => canvas.getByRole('option', {name: /sev/i}).click())
    await expect(input).toHaveValue('label:triage,"a11y (sev 1)"')
  },
}

export const InsertSuggestionForValueWhenExcludeIsSelected: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await userEvent.type(input, 'label:triage,a11y,')

    await waitFor(() => canvas.getByRole('option', {name: /Exclude/i}).click())
    await expect(input).toHaveValue('-label:')
  },
}

export const ShowSuggestionsWhenThereAreMultiplePrefixes: Story = {
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const input = canvas.getByRole('combobox')

    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await userEvent.type(input, 'a')
    await userEvent.keyboard('{ArrowDown}')
    await userEvent.keyboard('{Enter}')
    await expect(input).toHaveValue('assignee:')

    await userEvent.type(input, 'monalis')
    await expect(input).toHaveValue('assignee:monalis')
    await waitFor(async () => {
      await expect(getSuggestions(canvas)).toEqual([
        'monalisaMonalisa Octocat',
        'monalisa-wildcatMonalisa the Wildcat',
        'monalisacatMona',
        'octomonalisacatOcto Monalisa Cat',
        'littlecatMonalisa',
      ])
    })

    await userEvent.type(input, 'a')
    await expect(input).toHaveValue('assignee:monalisa')
    await waitFor(async () => {
      await expect(input).toHaveAttribute('aria-expanded', 'true')
      await expect(getSuggestions(canvas)).toEqual([
        'littlecatMonalisa',
        'monalisacatMona',
        'monalisa-wildcatMonalisa the Wildcat',
        'octomonalisacatOcto Monalisa Cat',
      ])
    })
  },
}
