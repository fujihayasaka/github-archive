import {Filter} from '@github-ui/filter'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {
  AssigneeFilterProviderWithCopilotSupport,
  AuthorFilterProviderWithCopilotSupport,
  InvolvesFilterProviderWithCopilotSupport,
  ReviewedByFilterProviderWithCopilotSupport,
  ReviewRequestedFilterProviderWithCopilotSupport,
} from '../copilot-user'
import {
  expectFilterValueToBe,
  selectSuggestion,
  setupUsersWithCopilotBotMockApi,
  updateFilterValue,
} from '../../../../test-utils/FilterProviderUtils'

describe('AssigneeFilterProviderWithCopilotSupport', () => {
  setupUsersWithCopilotBotMockApi()

  it('shows `Copilot` as a suggestion if showAtCopilot is true and a valid suggestion is found', async () => {
    const filterProviders = [new AssigneeFilterProviderWithCopilotSupport({showAtCopilot: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('assignee:')

    expect(screen.getByRole('option', {name: '@copilot, Your AI pair programmer'})).toBeInTheDocument()

    await selectSuggestion('Copilot')

    await expectFilterValueToBe('assignee:@copilot')
  })

  it('does not show `Copilot` as a suggestion if showAtCopilot is false', async () => {
    const filterProviders = [new AssigneeFilterProviderWithCopilotSupport({showAtCopilot: false})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('assignee:')

    expect(screen.queryByRole('option', {name: '@copilot, Your AI pair programmer'})).not.toBeInTheDocument()
  })
})

describe('AuthorFilterProviderWithCopilotSupport', () => {
  setupUsersWithCopilotBotMockApi()

  it('shows `Copilot` as a suggestion if showAtCopilot is true and a valid suggestion is found', async () => {
    const filterProviders = [new AuthorFilterProviderWithCopilotSupport({showAtCopilot: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('author:')

    expect(screen.getByRole('option', {name: '@copilot, Your AI pair programmer'})).toBeInTheDocument()

    await selectSuggestion('Copilot')

    await expectFilterValueToBe('author:@copilot')
  })

  it('does not show `Copilot` as a suggestion if showAtCopilot is false', async () => {
    const filterProviders = [new AuthorFilterProviderWithCopilotSupport({showAtCopilot: false})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('author:')

    expect(screen.queryByRole('option', {name: '@copilot, Your AI pair programmer'})).not.toBeInTheDocument()
  })
})

describe('ReviewedByFilterProviderWithCopilotSupport', () => {
  setupUsersWithCopilotBotMockApi()

  it('shows `Copilot` as a suggestion if showAtCopilot is true and a valid suggestion is found', async () => {
    const filterProviders = [new ReviewedByFilterProviderWithCopilotSupport({showAtCopilot: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('reviewed-by:')

    expect(screen.getByRole('option', {name: '@copilot, Your AI pair programmer'})).toBeInTheDocument()

    await selectSuggestion('Copilot')

    await expectFilterValueToBe('reviewed-by:@copilot')
  })

  it('does not show `Copilot` as a suggestion if showAtCopilot is false', async () => {
    const filterProviders = [new ReviewedByFilterProviderWithCopilotSupport({showAtCopilot: false})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('reviewed-by:')

    expect(screen.queryByRole('option', {name: '@copilot, Your AI pair programmer'})).not.toBeInTheDocument()
  })
})

describe('ReviewRequestedFilterProviderWithCopilotSupport', () => {
  setupUsersWithCopilotBotMockApi()

  it('shows `Copilot` as a suggestion if showAtCopilot is true and a valid suggestion is found', async () => {
    const filterProviders = [new ReviewRequestedFilterProviderWithCopilotSupport({showAtCopilot: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('review-requested:')

    expect(screen.getByRole('option', {name: '@copilot, Your AI pair programmer'})).toBeInTheDocument()

    await selectSuggestion('Copilot')

    await expectFilterValueToBe('review-requested:@copilot')
  })

  it('does not show `Copilot` as a suggestion if showAtCopilot is false', async () => {
    const filterProviders = [new ReviewRequestedFilterProviderWithCopilotSupport({showAtCopilot: false})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('review-requested:')

    expect(screen.queryByRole('option', {name: '@copilot, Your AI pair programmer'})).not.toBeInTheDocument()
  })
})

describe('InvolvesFilterProviderWithCopilotSupport', () => {
  setupUsersWithCopilotBotMockApi()

  it('shows `Copilot` as a suggestion if showAtCopilot is true and a valid suggestion is found', async () => {
    const filterProviders = [new InvolvesFilterProviderWithCopilotSupport({showAtCopilot: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('involves:')

    expect(screen.getByRole('option', {name: '@copilot, Your AI pair programmer'})).toBeInTheDocument()

    await selectSuggestion('Copilot')

    await expectFilterValueToBe('involves:@copilot')
  })

  it('does not show `Copilot` as a suggestion if showAtCopilot is false', async () => {
    const filterProviders = [new InvolvesFilterProviderWithCopilotSupport({showAtCopilot: false})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('involves:')

    expect(screen.queryByRole('option', {name: '@copilot, Your AI pair programmer'})).not.toBeInTheDocument()
  })
})
