import {render, type User} from '@github-ui/react-core/test-utils'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {screen, act, within} from '@testing-library/react'
import {RequiredReviewers, type RequiredReviewer, type PullRequestRuleMetadata} from '../RequiredReviewers'
import {
  mockRequiredReviewersWithMissingTeam as reviewers,
  mockRequiredReviewerMetadataWithMissingTeam as reviewerMetadata,
  mockRequiredReviewerSuggestions as suggestions,
  requiredReviewerField,
} from '../__tests__/helpers'
import type {SchemaField} from '../../../types/rules-types'
jest.useFakeTimers()
jest.setTimeout(20_000)

// Order should be reviewers who aren't found and then the remaining reviewers sorted by name
const expectedReviewerOrder = [reviewers[2], reviewers[1], reviewers[3], reviewers[0]] as RequiredReviewer[]

const renderComponent = ({...props}: Partial<Parameters<typeof RequiredReviewers>[0]> = {}) => {
  return render(
    <RequiredReviewers
      rulesetId={1}
      sourceType="repository"
      value={reviewers}
      metadata={reviewerMetadata}
      errors={[]}
      onValueChange={jest.fn()}
      field={requiredReviewerField as SchemaField}
      {...props}
    />,
  )
}

// When a user clicks the button, it opens the reviwer select panel, which returns suggestions
const openSelectReviewerPanel = async (user: User, buttonName: string = 'Select reviewer', element?: HTMLElement) => {
  if (element) {
    await user.click(within(element).getByRole('button', {name: new RegExp(buttonName, 'i')}))
  } else {
    await user.click(screen.getByRole('button', {name: new RegExp(buttonName, 'i')}))
  }
  await act(async () => {
    jest.runAllTimers()
    await mockFetch.resolvePendingRequest(/required_reviewer_suggestions/, suggestions)
  })
}

// When a user types in the search box, it filters the suggestions
const inputSearch = async (user: User, filter: string) => {
  await user.type(screen.getByPlaceholderText(/^Search reviewers/), filter)
  jest.runAllTimers()
  await mockFetch.resolvePendingRequest(
    /required_reviewer_suggestions\?q=/,
    suggestions.filter(suggestion => suggestion.name && suggestion.name.includes(filter)),
  )
}

describe('RequiredReviewers', () => {
  test('renders a toggled checkbox and a table with missing reviewers following by sorted reviewrs', () => {
    reviewerMetadata.requiredReviewers['T_105'] = {
      id: 5,
      globalRelayId: 'T_105',
      type: 'Team',
      name: 'Security',
      isNew: true, // This indicates that the reviewer was just added and is not yet saved
    }
    renderComponent({
      value: [...reviewers, {reviewer_id: 'T_105', minimum_approvals: 4, file_patterns: ['*']}],
      metadata: reviewerMetadata,
    })

    // Because we have reviewers, we expect the checkbox to be toggled
    expect(screen.getByRole('checkbox', {name: /Required review by specific teams/i})).toBeChecked()

    // We expect to see the number of reviewers in the header of the table
    expect(screen.getByText('5 reviewers')).toBeInTheDocument()

    // Under 10 reviewers, we don't show pagination
    expect(screen.queryByRole('navigation', {name: 'Pagination for required reviewers'})).not.toBeInTheDocument()

    // Because this is not readonly, we should have a button to add a reviewer
    expect(screen.getByRole('button', {name: /Add reviewer/i})).toBeInTheDocument()

    // Get all rows in the table (skipping the header)
    const rows = screen.getAllByRole('row').slice(1)

    // Check the first column of each of row
    // Order should be reviewer marked as "new", reviewers who aren't found, and then the remaining reviewers sorted by name
    const expectedOrder = ['Security', 'Reviewer not found', 'databases', 'GitAuth', 'repos']
    for (const [index, row] of rows.entries()) {
      const rowHeader = within(row).getByRole('rowheader')
      expect(rowHeader).toHaveTextContent(expectedOrder[index] as string)
    }
  })

  test('when readonly, renders without the ability to add reviewers', () => {
    renderComponent({readOnly: true})

    // Readonly does not show the checkbox
    expect(screen.queryByRole('checkbox', {name: /Required review by specific teams/i})).not.toBeInTheDocument()

    // Readonly does render text indicating that this is a rule
    expect(screen.getByText(/Required review by specific teams/i)).toBeInTheDocument()

    // Readonly does not render the add reviewer button
    expect(screen.queryByRole('button', {name: /Add reviewer/i})).not.toBeInTheDocument()

    // Get all rows in the table (skipping the header)
    const rows = screen.getAllByRole('row').slice(1)

    // Check the first column of each of the first 4 rows
    // Order should be reviewers who aren't found and then the remaining reviewers sorted by name
    const expectedOrder = ['Reviewer not found', 'databases', 'GitAuth', 'repos']
    for (const [index, row] of rows.entries()) {
      const rowHeader = within(row).getByRole('rowheader')
      expect(rowHeader).toHaveTextContent(expectedOrder[index] as string)
    }
  })

  test("when readonly without reviewers, doesn't include the rule", () => {
    renderComponent({readOnly: true, value: [], metadata: undefined})

    // Readonly does not show the checkbox
    expect(screen.queryByRole('checkbox', {name: /Required review by specific teams/i})).not.toBeInTheDocument()

    // When there are no values, we won't show anything about the rule
    expect(screen.queryByText(/Required review by specific teams/i)).not.toBeInTheDocument()

    // There's no table to render
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })

  test('clicking add reviewer will open a new reviewer dialog', async () => {
    const {user} = renderComponent()

    // Open dialog
    await user.click(screen.getByRole('button', {name: /Add reviewer/i}))
    const dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // The dialog shoud contain
    // Header says "Add reviewer"
    expect(within(dialog).getByRole('heading', {name: /Add reviewer/i})).toBeInTheDocument()

    // a select panel for reviewers
    expect(within(dialog).getByRole('button', {name: /Select reviewer/i})).toBeInTheDocument()

    // a dropdown for minimum approvals
    expect(within(dialog).getByRole('button', {name: /Approvals/i})).toBeInTheDocument()

    // a textarea input for file patterns
    expect(within(dialog).getByRole('textbox', {name: /File patterns/i})).toBeInTheDocument()

    // Buttons to cancel or be done
    expect(within(dialog).getByRole('button', {name: /Cancel/i})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: /Done/i})).toBeInTheDocument()
  })

  test('clicking edit reviewer will open an edit reviewer dialog for team', async () => {
    const {user} = renderComponent()

    // Find the row with GitAuth
    const gitAuthRow = screen.getByRole('row', {name: /GitAuth/})

    // Click the edit button to open the dialog
    const editButton = within(gitAuthRow).getByRole('button', {name: /Edit/i})
    await user.click(editButton)
    const dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // The dialog shoud contain
    // Header says "Edit reviewer"
    expect(within(dialog).getByRole('heading', {name: /Edit reviewer/i})).toBeInTheDocument()

    // a select panel should be set to the reviewer
    expect(within(dialog).getByRole('button', {name: /GitAuth/i})).toBeInTheDocument()

    // a dropdown for minimum approvals
    const minApprovals = within(dialog).getByRole('button', {name: /Approvals/i})
    expect(minApprovals).toBeInTheDocument()
    expect(minApprovals).toHaveTextContent('1')

    // a textarea input for file patterns
    const patterns = within(dialog).getByRole('textbox', {name: /File patterns/i})
    expect(patterns).toBeInTheDocument()
    expect(patterns).toHaveTextContent('*')

    // Buttons to delete, cancel, or be done
    expect(within(dialog).getByRole('button', {name: /Delete/i})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: /Cancel/i})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: /Done/i})).toBeInTheDocument()
  })

  test('clicking edit reviewer when the reviewer is not found will open an edit reviewer dialog', async () => {
    const {user} = renderComponent()

    // Find the row where the reviewer is not found
    const reviewer = screen.getByRole('row', {name: /Reviewer not found/})

    // Click the edit button to open the dialog
    const editButton = within(reviewer).getByRole('button', {name: /Edit/i})
    await user.click(editButton)
    const dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // The dialog shoud contain
    // Header says "Edit reviewer"
    expect(within(dialog).getByRole('heading', {name: /Edit reviewer/i})).toBeInTheDocument()

    // a select panel should be set to the reviewer
    expect(within(dialog).getByRole('button', {name: /Select reviewer/i})).toBeInTheDocument()

    // a dropdown for minimum approvals
    const minApprovals = within(dialog).getByRole('button', {name: /Approvals/i})
    expect(minApprovals).toBeInTheDocument()
    expect(minApprovals).toHaveTextContent('2')

    // a textarea input for file patterns
    const patterns = within(dialog).getByRole('textbox', {name: /File patterns/i})
    expect(patterns).toBeInTheDocument()

    // comma-separated list of file patterns are listed on separate lines
    expect(patterns).toHaveValue('**/*.md\n**/*.js')

    // Buttons to delete, cancel, or be done
    expect(within(dialog).getByRole('button', {name: /Delete/i})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: /Cancel/i})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: /Done/i})).toBeInTheDocument()
  })

  test('when readonly, clicking show reviewers will show the reviewers', async () => {
    const {user} = renderComponent({readOnly: true})

    // Find the row with GitAuth
    const gitAuthRow = screen.getByRole('row', {name: /GitAuth/})

    // Click the show reviewers button
    const showButton = within(gitAuthRow).getByRole('button', {name: /View/i})
    await user.click(showButton)

    // We expect to see the reviewers in a dialog
    const dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // The dialog shoud contain
    // Header says "Reviewers"
    expect(within(dialog).getByRole('heading', {name: /Reviewer details/i})).toBeInTheDocument()

    // Expect to see the reviewer's name
    expect(within(dialog).getByText('GitAuth')).toBeInTheDocument()

    // Expect to see number of approvals
    expect(within(dialog).getByText('1')).toBeInTheDocument()

    // Expect preformatted text with the file patterns
    expect(within(dialog).getByText('*')).toBeInTheDocument()

    // We don't expect a button to select the reviewer
    expect(within(dialog).queryByRole('button', {name: /GitAuth/i})).not.toBeInTheDocument()

    // We don't expect a button to change approvals
    expect(within(dialog).queryByRole('button', {name: /Approvals/i})).not.toBeInTheDocument()

    // We don't expect a textbox
    expect(within(dialog).queryByRole('textbox', {name: /File patterns/i})).not.toBeInTheDocument()

    // does not show delete or done buttons
    expect(within(dialog).queryByRole('button', {name: /Delete/i})).not.toBeInTheDocument()
    expect(within(dialog).queryByRole('button', {name: /Done/i})).not.toBeInTheDocument()
  })

  test('adding a reviewer will add to values', async () => {
    const onValueChange = jest.fn()

    const {user} = renderComponent({onValueChange})

    // Click the add reviewer button to open the dialog
    await user.click(screen.getByRole('button', {name: /Add reviewer/i}))
    const dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // Open the reviewer select panel and select a reviewer
    await openSelectReviewerPanel(user)
    const reviewer = await screen.findByRole('option', {selected: false, name: /Security/})
    expect(reviewer).toBeInTheDocument()
    await user.click(reviewer)

    // Select approvals
    await user.click(screen.getByRole('button', {name: /Approvals/i}))
    // Find the menu element
    const menu = await screen.findByRole('menu')
    // Find the li item within the menu that has the exact text "4"
    await user.click(within(menu).getByRole('menuitemradio', {name: '4'}))

    // Add text to textbox
    const filePatterns = within(dialog).getByRole('textbox', {name: /File patterns/i})
    await user.type(filePatterns, 'test')

    // Click done
    await user.click(within(dialog).getByRole('button', {name: /Done/i}))

    // The dialog should be closed and no longer visible
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    const expectedReviewers = [
      {
        reviewer_id: 'T_105', // this is the security team based on the suggestions
        minimum_approvals: 4,
        file_patterns: ['test'],
      },
      ...expectedReviewerOrder,
    ]
    // Calls onValueChange with the new values
    expect(onValueChange).toHaveBeenCalledWith(expectedReviewers)
  })

  test('removing a reviewer will remove them from the values', async () => {
    const onValueChange = jest.fn()

    const {user} = renderComponent({onValueChange})

    // Find the row with GitAuth
    const gitAuthRow = screen.getByRole('row', {name: /GitAuth/})

    // Click the edit button
    const editButton = within(gitAuthRow).getByRole('button', {name: /Edit/i})
    await user.click(editButton)
    const dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // click delete
    await user.click(within(dialog).getByRole('button', {name: /Delete/i}))

    // The dialog is closed
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    // Calls onValueChange with the remaining reviewers
    // filter out T_104 because it was deleted
    const expectedReviewers = expectedReviewerOrder.filter(reviewer => reviewer.reviewer_id !== 'T_104')
    expect(onValueChange).toHaveBeenCalledWith(expectedReviewers)
  })

  test('editing a reviewers approval and patterns will update the reviewer', async () => {
    const onValueChange = jest.fn()

    const {user} = renderComponent({onValueChange})

    // Find the row with GitAuth
    const gitAuthRow = screen.getByRole('row', {name: /GitAuth/})

    // Click the edit button
    const editButton = within(gitAuthRow).getByRole('button', {name: /Edit/i})
    await user.click(editButton)
    const dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // Select approvals
    await user.click(screen.getByRole('button', {name: /Approvals/i}))
    // Find the menu element
    const menu = await screen.findByRole('menu')
    // Find the li item within the menu that has the exact text "4"
    await user.click(within(menu).getByRole('menuitemradio', {name: '9'}))

    // Add text to textbox
    const filePatterns = within(dialog).getByRole('textbox', {name: /File patterns/i})
    await user.type(filePatterns, '\nfile1\nfile2\nfile3')

    // Click done
    await user.click(within(dialog).getByRole('button', {name: /Done/i}))

    // The dialog is closed
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    // Calls onValueChange with updated values
    const index = expectedReviewerOrder.findIndex(reviewer => reviewer.reviewer_id === 'T_104')
    const expectedReviewers = [
      ...expectedReviewerOrder.slice(0, index),
      {
        reviewer_id: 'T_104',
        minimum_approvals: 9,
        file_patterns: ['*', 'file1', 'file2', 'file3'],
      },
      ...expectedReviewerOrder.slice(index + 1),
    ]

    expect(onValueChange).toHaveBeenCalledWith(expectedReviewers)
  })

  test('editing a selected reviewer will update the reviewer in the table', async () => {
    const onValueChange = jest.fn()

    const {user} = renderComponent({onValueChange})

    // Find the row with GitAuth
    const gitAuthRow = screen.getByRole('row', {name: /GitAuth/})

    // Click the edit button
    const editButton = within(gitAuthRow).getByRole('button', {name: /Edit/i})
    await user.click(editButton)
    const dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // Oepn the reviewer select panel and select a reviewer
    await openSelectReviewerPanel(user, 'GitAuth', dialog)
    const reviewer = await screen.findByRole('option', {selected: false, name: /Security/})
    expect(reviewer).toBeInTheDocument()
    await user.click(reviewer)

    // Click done
    await user.click(within(dialog).getByRole('button', {name: /Done/i}))

    // The dialog is closed
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    // Replace the reviewer in the table
    const index = expectedReviewerOrder.findIndex(r => r.reviewer_id === 'T_104')
    const existingSettings = expectedReviewerOrder[index]
    const expectedReviewers = [
      ...expectedReviewerOrder.slice(0, index),
      {
        reviewer_id: 'T_105', // T_105 is the security team based on the suggestions
        minimum_approvals: existingSettings!.minimum_approvals,
        file_patterns: existingSettings!.file_patterns,
      },
      ...expectedReviewerOrder.slice(index + 1),
    ]

    expect(onValueChange).toHaveBeenCalledWith(expectedReviewers)
  })

  test('when over 10 reviewers, render pagination', async () => {
    const newReviewers = Array.from({length: 11}, (_, i) => ({
      reviewer_id: `T_${i}`,
      minimum_approvals: 1,
      file_patterns: ['*'],
    })) as RequiredReviewer[]

    // Generate metadata
    const metadata = {
      requiredReviewers: Object.fromEntries(
        newReviewers.map((r, index) => [
          r.reviewer_id,
          {
            id: index + 1,
            globalRelayId: r.reviewer_id,
            type: 'Team',
            name: `Team ${r.reviewer_id}`,
          },
        ]),
      ),
    } as PullRequestRuleMetadata

    const {user} = renderComponent({value: newReviewers, metadata})

    // Show pagination
    const nav = screen.getByRole('navigation', {name: 'Pagination for required reviewers'})
    expect(nav).toBeInTheDocument()

    // Expect a next button
    const nextButton = within(nav).getByRole('button', {name: /Next/})
    expect(nextButton).toBeInTheDocument()

    // Expect to see the first 10 reviewers (excludes team-9 because team 1, 10, and 11 come first)
    const firstPageReviewers = screen.queryAllByRole('row').slice(1)
    expect(firstPageReviewers).toHaveLength(10)
    expect(screen.queryByRole('row', {name: /Team T_9/})).not.toBeInTheDocument()

    // Click next
    await user.click(nextButton)

    // Expect to see team 9 in the first row of the second page
    const secondPageReviewers = screen.queryAllByRole('row').slice(1)
    expect(secondPageReviewers).toHaveLength(1)
    expect(screen.getByRole('row', {name: /Team T_9/})).toBeInTheDocument()
  })

  test('renders error when reviewers are not unique', async () => {
    const onValueChange = jest.fn()

    const {user} = renderComponent({onValueChange})

    // Click the add reviewer button to open the dialog
    await user.click(screen.getByRole('button', {name: /Add reviewer/i}))
    let dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // Open the reviewer select panel and select a reviewer
    await openSelectReviewerPanel(user)
    const reviewer = await screen.findByRole('option', {selected: false, name: /GitAuth/})
    expect(reviewer).toBeInTheDocument()
    await user.click(reviewer)

    // Expect to see an error
    expect(await within(dialog).findByText('This team is already added as a reviewer')).toBeInTheDocument()

    // Select approvals
    await user.click(screen.getByRole('button', {name: /Approvals/i}))
    // Find the menu element
    const menu = await screen.findByRole('menu')
    // Find the li item within the menu that has the exact text "4"
    await user.click(within(menu).getByRole('menuitemradio', {name: '4'}))

    // Add text to textbox
    const filePatterns = within(dialog).getByRole('textbox', {name: /File patterns/i})
    await user.type(filePatterns, 'test')

    // Click done
    await user.click(within(dialog).getByRole('button', {name: /Done/i}))

    // The dialog should still be visible
    dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // Expect to see an error
    expect(await within(dialog).findByText('This team is already added as a reviewer')).toBeInTheDocument()

    // We won't update the values because there is an error
    expect(onValueChange).not.toHaveBeenCalled()
  })

  test('renders error when a reviewer is not selected and when there are not file patterns', async () => {
    const onValueChange = jest.fn()

    const {user} = renderComponent({onValueChange})

    // Click the add reviewer button to open the dialog
    await user.click(screen.getByRole('button', {name: /Add reviewer/i}))
    let dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // Click done
    await user.click(within(dialog).getByRole('button', {name: /Done/i}))

    // The dialog should still be visible
    dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // Expect to see errors
    expect(await within(dialog).findByText('A reviewer must be selected')).toBeInTheDocument()
    expect(await within(dialog).findByText('At least one file pattern must be specified')).toBeInTheDocument()

    // We won't update the values because there are errors
    expect(onValueChange).not.toHaveBeenCalled()
  })

  test('filter reviewers', async () => {
    const {user} = renderComponent()
    await user.click(screen.getByRole('button', {name: /Add reviewer/i}))
    const dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()
    await openSelectReviewerPanel(user)
    // Get all options
    const options = await screen.findAllByRole('option')
    // Options length should be greater than 1
    expect(options.length).toBeGreaterThan(1)
    await act(async () => {
      await inputSearch(user, 'Sec')
    })
    // Expect only 1 option to be visible
    // The option should be the security team
    await screen.findByRole('option', {name: /Security/})
    expect(await screen.findAllByRole('option')).toHaveLength(1)
    expect(await screen.findByRole('option', {name: /Security/})).toBeInTheDocument()
  })

  test('filter reviewers with no results', async () => {
    const {user} = renderComponent()
    await user.click(screen.getByRole('button', {name: /Add reviewer/i}))
    const dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()
    await openSelectReviewerPanel(user)
    // Get all options
    const options = await screen.findAllByRole('option')
    // Options length should be greater than 1
    expect(options.length).toBeGreaterThan(1)
    await act(async () => {
      await inputSearch(user, 'random text team')
    })
    expect(screen.queryAllByRole('option')).toHaveLength(0)
    expect(await screen.findByRole('listbox')).toHaveTextContent('No teams found')
  })
})
