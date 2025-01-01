import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import type {RepoModel} from '../../types'
import {useFilteredModels} from '../../hooks/use-filtered-models'
import {getModelRepoPromptsAppPayload, mockModel, mockOrgAllowedModel} from '../../test-utils/mock-data'
import {PromptList} from '../PromptList'
import {mockPrompts} from './mocks'

const mockUseFilteredModels = useFilteredModels as jest.Mock
jest.mock('@github-ui/github-models-repo/UseFilteredModels', () => ({
  useFilteredModels: jest.fn(),
}))

describe('PromptList', () => {
  beforeEach(() => {
    jest.clearAllMocks()

    const availableModels: RepoModel[] = [mockModel(), mockOrgAllowedModel]
    mockUseFilteredModels.mockReturnValue({
      availableModels,
      isLoadingModels: false,
    })
  })

  test('renders when no prompts are provided', async () => {
    const appPayload = getModelRepoPromptsAppPayload()

    render(<PromptList canEdit prompts={[]} totalPrompts={0} repository={appPayload.repository} />, {appPayload})

    expect(screen.getByText('0 prompts found')).toBeInTheDocument()
    expect(screen.queryByText('View all')).not.toBeInTheDocument()
    expect(screen.getByText('Create a prompt')).toBeInTheDocument()
    expect(screen.queryByRole('navigation', {name: 'Pagination'})).not.toBeInTheDocument()
  })

  test('renders with custom header text', () => {
    const appPayload = getModelRepoPromptsAppPayload()

    render(
      <PromptList
        canEdit
        prompts={[]}
        totalPrompts={0}
        repository={appPayload.repository}
        headerText="Custom Header"
      />,
      {appPayload},
    )

    expect(screen.getByText('Custom Header')).toBeInTheDocument()
    expect(screen.queryByText('View all')).not.toBeInTheDocument()
    expect(screen.getByText('Create a prompt')).toBeInTheDocument()
    expect(screen.queryByRole('navigation', {name: 'Pagination'})).not.toBeInTheDocument()
  })

  test('renders when prompts are provided', () => {
    const appPayload = getModelRepoPromptsAppPayload()
    const prompts = mockPrompts(8)

    render(<PromptList canEdit prompts={prompts} totalPrompts={prompts.length} repository={appPayload.repository} />, {
      appPayload,
    })

    expect(screen.getByText('8 prompts found')).toBeInTheDocument()
    expect(screen.queryByText('View all')).not.toBeInTheDocument()
    expect(screen.queryByText('Create a prompt')).not.toBeInTheDocument()
    expect(screen.queryByRole('navigation', {name: 'Pagination'})).not.toBeInTheDocument()

    for (const prompt of prompts) {
      expect(screen.getByText(prompt.name)).toBeInTheDocument()
      expect(screen.getByText(prompt.description)).toBeInTheDocument()
    }
  })

  test('renders a View all link when showViewAll is true', () => {
    const prompts = mockPrompts()
    const appPayload = getModelRepoPromptsAppPayload()

    render(
      <PromptList
        canEdit
        prompts={prompts}
        page={1}
        totalPages={2}
        totalPrompts={prompts.length + 1}
        repository={appPayload.repository}
        showViewAll
      />,
      {appPayload},
    )

    expect(screen.getByText('View all')).toBeInTheDocument()
    expect(screen.getByRole('navigation', {name: 'Pagination'})).toBeInTheDocument()
  })

  test('lets the user know they need write permissions to create prompts', () => {
    const appPayload = getModelRepoPromptsAppPayload()
    render(<PromptList canEdit={false} prompts={[]} totalPrompts={0} repository={appPayload.repository} />, {
      appPayload,
    })

    expect(
      screen.getByText('Get write permissions or higher for this repository to create and manage prompts.'),
    ).toBeInTheDocument()
  })
})
