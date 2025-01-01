import {isFeatureEnabled} from '@github-ui/feature-flags'
import {render, screen, waitFor, within} from '@testing-library/react'
import {userEvent} from '@testing-library/user-event'
import type {OperationDescriptor} from 'relay-runtime'
import {createMockEnvironment as createRelayMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'

import type {Owner} from '../../../client/api/common-contracts'
import {useEnabledFeatures} from '../../../client/hooks/use-enabled-features'
import {Resources} from '../../../client/strings'
import {mockParentIssues} from '../../../mocks/data/parent-issues'
import {customColumnFactory} from '../../factories/columns/custom-column-factory'
import {systemColumnFactory} from '../../factories/columns/system-column-factory'
import {stubGetFilterSuggestions} from '../../mocks/api/memex'
import {mockUseHasColumnData} from '../../mocks/hooks/use-has-column-data'
import {asMockHook} from '../../mocks/stub-utilities'
import {setupTableView} from '../../test-app-wrapper'

// Forgo debounced update to query parameters when typing in the filter bar, which currently falls outside of the focus
// for this test. Using jest.useFakeTimers and jest.advanceTimersByTime does not work well when rendered inside of the AppContext,
// which involves many timer interactions.
jest.mock('lodash-es/debounce', () =>
  jest.fn(fn => {
    fn.cancel = jest.fn()
    fn.flush = jest.fn()
    return fn
  }),
)

const sendEventMock = jest.fn()
jest.mock('@github/hydro-analytics-client', () => ({
  AnalyticsClient: class AnalyticsClient {
    sendEvent(...args: Array<unknown>) {
      sendEventMock(...args)
    }
  },
}))

jest.mock('../../../client/hooks/use-enabled-features')

const mockedIsFeatureEnabled = jest.mocked(isFeatureEnabled)
jest.mock('@github-ui/feature-flags', () => ({isFeatureEnabled: jest.fn()}))

const orgOwner = {
  id: 1,
  login: 'github',
  name: 'GitHub',
  avatarUrl: 'https://foo.bar/avatar.png',
  type: 'organization',
} satisfies Owner

const relayEnvWithSuggestedIssueTypes = () => {
  const relayEnvironment = createRelayMockEnvironment()
  relayEnvironment.mock.queueOperationResolver((operation: OperationDescriptor) =>
    MockPayloadGenerator.generate(operation, {
      Organization: () => ({
        projectV2: {
          suggestedIssueTypeNames: ['Epic', 'Feature', 'Task', 'Bug', 'Batch', 'Initiative', 'Enhancement'],
        },
      }),
    }),
  )
  return relayEnvironment
}

describe('Filter bar', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    mockUseHasColumnData()
    asMockHook(useEnabledFeatures).mockReturnValue({
      memex_table_without_limits: true,
      issue_types: true,
      sub_issues: true,
      memex_mwl_use_type_provider: true,
      memex_mwl_unique_filter_suggestions: true,
      mwl_filter_bar_validation: true,
    })
  })

  function renderViewWithFilter(relayEnvironment?: RelayMockEnvironment) {
    const columns = [
      systemColumnFactory.title().build(),
      systemColumnFactory.assignees().build(),
      systemColumnFactory.status({optionNames: ['Todo', 'In progress', 'Done']}).build(),
      systemColumnFactory.labels().build(),
      systemColumnFactory.linkedPullRequests().build(),
      systemColumnFactory.repository().build(),
      systemColumnFactory.reviewers().build(),
      systemColumnFactory.milestone().build(),
      systemColumnFactory.issueType().build(),
      systemColumnFactory.parentIssue().build(),
      customColumnFactory.date().build({name: 'Date'}),
      customColumnFactory
        .iteration({
          configuration: {
            startDay: 1,
            duration: 7,
            iterations: [{startDate: '2022-07-07', title: 'Sprint 1', titleHtml: 'Sprint 1', duration: 7, id: '1'}],
            completedIterations: [],
          },
        })
        .build({name: 'Iteration'}),
      customColumnFactory.number().build({name: 'Number'}),
      customColumnFactory.singleSelect({optionNames: ['One', 'Two', 'Three']}).build({name: 'Single select'}),
      customColumnFactory.text().build({name: 'Text'}),
    ]

    const {Table} = setupTableView({columns, owner: orgOwner, relayEnvironment})
    render(<Table />)
  }

  function getInput() {
    return screen.getByPlaceholderText(Resources.filterByKeyboardOrByField)
  }

  async function getSuggestions() {
    try {
      return await within(screen.getByTestId('filter-bar-component')).findAllByRole('option')
    } catch {
      return []
    }
  }

  function getSuggestionsDropdown() {
    return screen.getByLabelText('Suggestions')
  }

  async function getSuggestionWithLabel(label: string | RegExp) {
    const suggestionsDropdown = getSuggestionsDropdown()
    try {
      return await within(suggestionsDropdown).findAllByLabelText(label)
    } catch {
      return []
    }
  }

  async function getHasFilterSuggestionValues() {
    renderViewWithFilter()
    const expectedSuggestions = [
      'Assignee, Has',
      'Date, Has',
      'Iteration, Has',
      'Label, Has',
      'Linked pull requests, Has',
      'Milestone, Has',
      'Number, Has',
      'Parent issue, Has',
      'Repository, Has',
      'Reviewers, Has',
      'Single select, Has',
      'Status, Has',
      'Text, Has',
      'Type, Has',
    ]
    const input = getInput()
    await userEvent.type(input, 'has:')
    const statusSuggestion = await getSuggestionWithLabel(/^Status/)
    const suggestions = await getSuggestions()

    expect(statusSuggestion.length).toBe(1)
    expect(suggestions.length).toBe(expectedSuggestions.length)
    const ariaLabels = suggestions.map(suggestion => suggestion.getAttribute('aria-label'))
    return {expectedSuggestions, actualSuggestions: ariaLabels}
  }

  it('shows suggestions on input focus', async () => {
    renderViewWithFilter()
    const input = getInput()
    await userEvent.click(input)
    const suggestions = await getSuggestions()

    expect(suggestions.length).toBe(13)
  })

  it('shows suggestion for No filter', async () => {
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'no')
    const noSuggestion = await getSuggestionWithLabel(/^No/)

    expect(noSuggestion.length).toBe(1)
  })

  it('shows suggestions for No filter values', async () => {
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'no:')
    const statusSuggestion = await getSuggestionWithLabel(/^Status/)
    const suggestions = await getSuggestions()

    expect(statusSuggestion.length).toBe(1)
    expect(suggestions.length).toBe(14)
  })

  it('shows suggestions for Has filter values without feature flag (using legacy HasFilterProvider)', async () => {
    const {expectedSuggestions, actualSuggestions} = await getHasFilterSuggestionValues()
    expect(actualSuggestions).toEqual(expectedSuggestions)
  })

  it('shows suggestions for Has filter with feature flag (not using legacy HasFilterProvider)', async () => {
    mockedIsFeatureEnabled.mockImplementation(flag => flag === 'issues_advanced_search_has_filter')
    const {expectedSuggestions, actualSuggestions} = await getHasFilterSuggestionValues()
    expect(actualSuggestions).toEqual(expectedSuggestions)
    mockedIsFeatureEnabled.mockRestore()
  })

  it('shows suggestion for Is filter', async () => {
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'is')
    const isSuggestion = await getSuggestionWithLabel(/^Is/)

    expect(isSuggestion.length).toBe(1)
  })

  it('shows suggestions for the Reason filter', async () => {
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'reason:')

    const completedSuggestion = await getSuggestionWithLabel(/^Completed/)
    const notPlannedSuggestion = await getSuggestionWithLabel(/^Not planned/)
    const reopenedSuggestion = await getSuggestionWithLabel(/^Reopened/)
    const duplicateSuggestion = await getSuggestionWithLabel(/^Duplicate/)
    const suggestions = await getSuggestions()

    expect(completedSuggestion.length).toBe(1)
    expect(notPlannedSuggestion.length).toBe(1)
    expect(reopenedSuggestion.length).toBe(1)
    expect(duplicateSuggestion.length).toBe(1)
    expect(suggestions.length).toBe(5)
  })

  it('shows suggestions for the Updated filter', async () => {
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'updated:')

    const todaySuggestion = await getSuggestionWithLabel(/^Today/)
    expect(todaySuggestion.length).toBe(1)
  })

  it('shows suggestions for State filter', async () => {
    renderViewWithFilter()
    const input = getInput()
    await userEvent.click(input)
    let stateSuggestion = await getSuggestionWithLabel(/^State/)

    expect(stateSuggestion.length).toBe(0)

    await userEvent.type(input, 'state')
    stateSuggestion = await getSuggestionWithLabel(/^State/)

    expect(stateSuggestion.length).toBe(1)
  })

  it('includes State filter values in suggestions for Is filter values (legacy functionality)', async () => {
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'is:')
    const typeSuggestion = await getSuggestionWithLabel(/^Issue/)
    const stateSuggestion = await getSuggestionWithLabel(/^Open/)
    const suggestions = await getSuggestions()

    expect(typeSuggestion.length).toBe(1)
    expect(stateSuggestion.length).toBe(1)
    // <Exclude>, Open, Closed, Draft, Merged, Pull Request, Issue
    expect(suggestions.length).toBe(7)
  })

  it('supports Type field for org-owned projects', async () => {
    const relayEnv = relayEnvWithSuggestedIssueTypes()
    renderViewWithFilter(relayEnv)
    const input = getInput()
    await userEvent.type(input, 'type')
    const typeSuggestion = await getSuggestionWithLabel(/^Type/)
    await userEvent.click(typeSuggestion[0])

    await waitFor(async () => expect(await getSuggestions()).toHaveLength(8))

    const suggestions = await getSuggestions()
    expect(suggestions[0]).toHaveTextContent('No type')
    expect(suggestions[1]).toHaveTextContent('Epic')

    // Does not include suggestions for legacy 'type' filter
    expect(await getSuggestionWithLabel(/^Issue/)).toHaveLength(0)
    expect(await getSuggestionWithLabel(/^Pull Request/)).toHaveLength(0)
  })

  it('supports parent issue field', async () => {
    renderViewWithFilter()
    const filterStub = stubGetFilterSuggestions(mockParentIssues)
    const input = getInput()
    await userEvent.type(input, 'parent')
    const parentIssueSuggestion = await getSuggestionWithLabel(/^Parent issue/)
    await userEvent.click(parentIssueSuggestion[0])

    await waitFor(() => expect(filterStub).toHaveBeenCalled())
    await waitFor(async () => expect(await getSuggestions()).toHaveLength(mockParentIssues.length + 2)) // Adding 2 for No and Exclude)

    const parentIssues = await getSuggestionWithLabel(`${mockParentIssues[0].title}, Parent issue`)
    expect(parentIssues).toHaveLength(1)
    expect(parentIssues[0]).toHaveTextContent(mockParentIssues[0].nwoReference)

    await userEvent.click(parentIssues[0])
    await waitFor(() => expect(input).toHaveValue(`parent-issue:${mockParentIssues[0].nwoReference}`))
  })

  it('sorts parent issue by updated date', async () => {
    renderViewWithFilter()
    mockParentIssues[0].updatedAt = '2022-10-30T00:00:00Z'
    mockParentIssues[1].updatedAt = '2023-10-30T00:00:00Z'
    mockParentIssues[2].updatedAt = '2024-10-30T00:00:00Z'
    const filterStub = stubGetFilterSuggestions(mockParentIssues)
    const input = getInput()
    await userEvent.type(input, 'parent')
    const parentIssueSuggestion = await getSuggestionWithLabel(/^Parent issue/)
    await userEvent.click(parentIssueSuggestion[0])

    await waitFor(() => expect(filterStub).toHaveBeenCalled())

    const parentIssues = await getSuggestions()
    expect(parentIssues).toHaveLength(5) // Adding 2 for No and Exclude)
    expect(parentIssues[2]).toHaveTextContent(mockParentIssues[2].nwoReference)
    expect(parentIssues[3]).toHaveTextContent(mockParentIssues[1].nwoReference)
    expect(parentIssues[4]).toHaveTextContent(mockParentIssues[0].nwoReference)
  })

  it('does not request parent issue suggestions more than once', async () => {
    renderViewWithFilter()
    const filterStub = stubGetFilterSuggestions(mockParentIssues)
    const input = getInput()
    await userEvent.type(input, 'parent')
    const parentIssueSuggestion = await getSuggestionWithLabel(/^Parent issue/)
    await userEvent.click(parentIssueSuggestion[0])

    await waitFor(() => expect(filterStub).toHaveBeenCalled())
    await waitFor(async () => expect(await getSuggestions()).toHaveLength(mockParentIssues.length + 2)) // Adding 2 for No and Exclude)

    await userEvent.type(input, 'one')
    await waitFor(async () => expect(await getSuggestions()).toHaveLength(mockParentIssues.length))

    expect(filterStub).toHaveBeenCalledTimes(1)
  })

  it('supports field names containing parentheses', async () => {
    const {Table} = setupTableView({
      columns: [
        systemColumnFactory.status({optionNames: ['Todo', 'In progress', 'Done']}).build(),
        customColumnFactory.singleSelect({optionNames: ['One', 'Two']}).build({name: 'Name (parentheses)'}),
      ],
    })
    render(<Table />)
    const input = getInput()
    await userEvent.type(input, 'name')

    const suggestions = await getSuggestionWithLabel(/^Name \(parentheses\)/)
    expect(suggestions.length).toBe(1)

    await userEvent.click(suggestions[0])
    const ariaLabels = (await getSuggestions()).map(suggestion => suggestion.getAttribute('aria-label'))
    expect(ariaLabels).toEqual([
      'No Name (parentheses), Name (parentheses)',
      'Exclude name-(parentheses)',
      'One, Name (parentheses)',
      'Two, Name (parentheses)',
    ])

    const optionSuggestion = await getSuggestionWithLabel(/^One/)
    expect(optionSuggestion.length).toBe(1)
  })

  it('supports field names containing matched quotes', async () => {
    const {Table} = setupTableView({
      columns: [
        systemColumnFactory.status({optionNames: ['Todo', 'In progress', 'Done']}).build(),
        customColumnFactory.singleSelect({optionNames: ['One', 'Two']}).build({name: 'Name \'Name\' "Name"'}),
      ],
    })
    render(<Table />)
    const input = getInput()
    await userEvent.type(input, 'name')

    const suggestions = await getSuggestionWithLabel(/^Name 'Name' "Name"/)
    expect(suggestions.length).toBe(1)

    await userEvent.click(suggestions[0])
    const optionSuggestion = await getSuggestionWithLabel(/^One/)

    expect(optionSuggestion.length).toBe(1)
  })

  it('shows suggestions for the Date filter', async () => {
    mockedIsFeatureEnabled.mockImplementation(flag => flag === 'issues_advanced_search_has_filter')
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'date:')

    const suggestions = await getSuggestions()
    const ariaLabels = suggestions.map(suggestion => suggestion.getAttribute('aria-label'))
    const today = new Date()
    const formattedToday = new Intl.DateTimeFormat('en-US', {
      month: 'long',
      day: 'numeric',
      year: 'numeric',
    }).format(today)

    expect(ariaLabels).toEqual([
      'No Date, Date',
      'Has Date, Date',
      'Exclude date',
      'Today, Date',
      'Yesterday, Date',
      'Past 7 days, Date',
      'Past 30 days, Date',
      'Past year, Date',
      `${formattedToday}, Date`,
    ])
    mockedIsFeatureEnabled.mockRestore()
  })

  it('supports iso8601 Date fields', async () => {
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'date:2025-01-01 ') // 2025-01-01 is a valid iso8601 Date format

    await waitFor(() => expect(screen.queryByTestId('validation-error-list')).not.toBeInTheDocument())
  })

  it('supports iso8601 for updated queries', async () => {
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'updated:2025-01-01 ') // 2025-01-01 is a valid iso8601 Date format

    await waitFor(() => expect(screen.queryByTestId('validation-error-list')).not.toBeInTheDocument())
  })

  it.each([
    'date:asdasdasd',
    'date:123123123',
    'date:1-1-1',
    'date:2025-1-1',
    'date:2025-01-1',
    'date:2025-1-01',
    'date:>2025-1-1',
    'date:>=2025-01-1',
    'date:<2025-1-01',
    'date:<=2025-01-1',
    'updated:asdasdasd',
    'updated:123123123',
    'updated:1-1-1',
    'updated:2025-1-1',
    'updated:2025-01-1',
    'updated:2025-1-01',
    'updated:>2025-01-1',
    'updated:>=2025-1-01',
    'updated:<2025-01-1',
    'updated:<=2025-1-01',
  ])('shows validation message for invalid iso8601 Date format for %s', async date => {
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, `${date} `)

    await waitFor(() => expect(screen.getByTestId('validation-error-list')).toBeVisible())
  })

  it('shows suggestions for the Number filter', async () => {
    mockedIsFeatureEnabled.mockImplementation(flag => flag === 'issues_advanced_search_has_filter')
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'number:')

    const suggestions = await getSuggestions()
    const ariaLabels = suggestions.map(suggestion => suggestion.getAttribute('aria-label'))

    expect(ariaLabels).toEqual(['No Number, Number', 'Has Number, Number', 'Exclude number'])
    mockedIsFeatureEnabled.mockRestore()
  })

  it('shows suggestions for the Text filter', async () => {
    mockedIsFeatureEnabled.mockImplementation(flag => flag === 'issues_advanced_search_has_filter')
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'text:')

    const suggestions = await getSuggestions()
    const ariaLabels = suggestions.map(suggestion => suggestion.getAttribute('aria-label'))

    expect(ariaLabels).toEqual(['No Text, Text', 'Has Text, Text', 'Exclude text'])
    mockedIsFeatureEnabled.mockRestore()
  })

  it('shows suggestions for the Linked pull requests filter', async () => {
    mockedIsFeatureEnabled.mockImplementation(flag => flag === 'issues_advanced_search_has_filter')
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'linked-pull-requests:')

    const suggestions = await getSuggestions()
    const ariaLabels = suggestions.map(suggestion => suggestion.getAttribute('aria-label'))

    expect(ariaLabels).toEqual([
      'No Linked pull requests, Linked pull requests',
      'Has Linked pull requests, Linked pull requests',
      'Exclude linked-pull-requests',
    ])
    mockedIsFeatureEnabled.mockRestore()
  })

  it('shows suggestions for Single select filters', async () => {
    mockedIsFeatureEnabled.mockImplementation(flag => flag === 'issues_advanced_search_has_filter')
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'single-select:')

    const suggestions = await getSuggestions()
    const ariaLabels = suggestions.map(suggestion => suggestion.getAttribute('aria-label'))

    expect(ariaLabels).toEqual([
      'No Single select, Single select',
      'Has Single select, Single select',
      'Exclude single-select',
      'One, Single select',
      'Two, Single select',
      'Three, Single select',
    ])
    mockedIsFeatureEnabled.mockRestore()
  })

  it('shows iteration macro filters first, followed by custom iterations', async () => {
    mockedIsFeatureEnabled.mockImplementation(flag => flag === 'issues_advanced_search_has_filter')
    renderViewWithFilter()
    const input = getInput()
    await userEvent.type(input, 'iteration')
    const iterationSuggestion = await getSuggestionWithLabel(/^Iteration/)
    expect(iterationSuggestion.length).toBe(1)
    await userEvent.click(iterationSuggestion[0])
    const suggestions = await getSuggestions()
    const ariaLabels = suggestions.map(suggestion => suggestion.getAttribute('aria-label'))
    expect(ariaLabels).toEqual([
      'No Iteration, Iteration',
      'Has Iteration, Iteration',
      'Exclude iteration',
      'Current iteration, Iteration',
      'Next iteration, Iteration',
      'Previous iteration, Iteration',
      'Sprint 1, Iteration', // Custom iteration from test data
    ])
    mockedIsFeatureEnabled.mockRestore()
  })
})
