import {render, RouteContext} from '@github-ui/react-core/test-utils'
import {screen, within, waitFor} from '@testing-library/react'
import {PromptListPagination} from '../PromptListPagination'
import type {ModelRepoPromptsRoutePayload} from '../../types'
import {mockPrompt} from './mocks'

const onPromptsLoaded = jest.fn().mockName('onPromptsLoaded')

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('PromptListPagination', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  it('renders when there is more than one page', async () => {
    const repo = {ownerLogin: 'foo', name: 'bar'}
    const secondPagePrompt = mockPrompt('Whee')

    const {user} = render(
      <PromptListPagination repository={repo} page={1} totalPages={2} onPromptsLoaded={onPromptsLoaded} />,
      {search: ''},
    )

    const pageNav = screen.getByRole('navigation', {name: 'Pagination'})
    expect(pageNav).toBeInTheDocument()
    const firstPageLink = within(pageNav).getByRole('link', {name: 'Page 1'})
    expect(firstPageLink).toBeInTheDocument()
    expect(firstPageLink).toHaveAttribute('href', '/foo/bar/models/prompts')
    expect(firstPageLink).toHaveAttribute('aria-current', 'page')
    const secondPageLink = within(pageNav).getByRole('link', {name: 'Page 2'})
    expect(secondPageLink).toBeInTheDocument()
    expect(secondPageLink).toHaveAttribute('href', '/foo/bar/models/prompts?page=2')
    expect(secondPageLink).not.toHaveAttribute('aria-current')
    expect(within(pageNav).queryByRole('link', {name: 'Page 3'})).not.toBeInTheDocument()

    const payload: ModelRepoPromptsRoutePayload = {prompts: [secondPagePrompt], page: 2, totalPages: 2}
    mockVerifiedFetchJSON.mockResolvedValue({ok: true, json: () => ({payload})})

    await user.click(secondPageLink)

    expect(onPromptsLoaded).toHaveBeenCalledWith([secondPagePrompt], 2)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/foo/bar/models/prompts?page=2')
    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)

    // Wait for the URL to be updated asynchronously
    await waitFor(() => {
      expect(RouteContext.location?.search).toEqual('?page=2')
    })
  })

  it('does not render when there is only one page', () => {
    const repo = {ownerLogin: 'foo', name: 'bar'}

    render(<PromptListPagination repository={repo} page={1} totalPages={1} onPromptsLoaded={onPromptsLoaded} />, {
      search: '',
    })

    expect(screen.queryByRole('navigation', {name: 'Pagination'})).not.toBeInTheDocument()
    expect(onPromptsLoaded).not.toHaveBeenCalled()
    expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()
  })
})
