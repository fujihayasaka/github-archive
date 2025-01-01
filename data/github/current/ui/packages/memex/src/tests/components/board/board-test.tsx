import {render, screen, waitFor} from '@testing-library/react'
import userEvent from '@testing-library/user-event'

import {useHasColumnData} from '../../../client/state-providers/columns/use-has-column-data'
import {draftIssueFactory} from '../../factories/memex-items/draft-issue-factory'
import {asMockHook} from '../../mocks/stub-utilities'
import {setupBoardView} from '../../test-app-wrapper'
import {mockGetBoundingClientRect, setupPaginatedBoard} from './board-test-helper'

/**
 * Without mocking this hook we will issue an additional server call because the
 * data that we have for our items does not line up with the columns that are defined for the
 * test. This additional server call is async and will respond _after_ the test has completed,
 * causing noise in the test console when we try to `setState` outside of an `act` block.
 *
 * We could try to always make sure that our column values line up with our columns, to prevent
 * this call; however, since this behavior isn't really what we're focused on testing in
 * this test suite, we instead just mock out the hook entirely.
 */
jest.mock('../../../client/state-providers/columns/use-has-column-data')

describe('Board View', () => {
  beforeAll(() => {
    mockGetBoundingClientRect()
    asMockHook(useHasColumnData).mockReturnValue({hasColumnData: () => true})
  })

  it('should render a memex item', () => {
    const {Board} = setupBoardView({
      items: [draftIssueFactory.withTitleColumnValue('Explore performance issues').build()],
    })
    render(<Board />)

    expect(screen.getAllByTestId('board-view-column-card')).toHaveLength(1)
    expect(screen.getByText('Explore performance issues')).toBeInTheDocument()
  })

  it('displays new Single Select option created in view as new column', async () => {
    const {Board, statusField} = setupPaginatedBoard(['memex_mwl_refresh_groups'])
    render(<Board />)
    const visibleColumns = await waitFor(() => screen.findAllByTestId('board-view-column-title-text'))
    expect(visibleColumns).toHaveLength(statusField?.settings?.options?.length ?? 0)
    const addNewColumnButton = await waitFor(() => screen.findByTestId('add-new-column-button'))
    await userEvent.click(addNewColumnButton)

    const button = await waitFor(() => screen.findByTestId('add-new-column-option-button'))
    await userEvent.click(button)

    const input = await waitFor(() => screen.findByTestId('single-select-option-text-input'))
    await userEvent.type(input, 'New Option')
    const submitButton = await waitFor(() => screen.findByTestId('save-single-select-option-button'))
    await userEvent.click(submitButton)

    const newVisibleColumns = await waitFor(() => screen.findAllByTestId('board-view-column-title-text'))
    expect(newVisibleColumns).toHaveLength(visibleColumns.length + 1)
  })
})
