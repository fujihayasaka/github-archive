import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {useFilteredModels} from '../../hooks/use-filtered-models'
import {findModel} from '../../routes/prompt/models'
import {getModelRepoPromptsAppPayload, mockModel, mockOrgAllowedModel} from '../../test-utils/mock-data'
import {PromptLabel} from '../PromptLabel'

const mockUseFilteredModels = useFilteredModels as jest.Mock
jest.mock('@github-ui/github-models-repo/UseFilteredModels', () => ({
  useFilteredModels: jest.fn(),
}))

const mockFindModel = findModel as jest.Mock
jest.mock('../../routes/prompt/models')

const model = mockModel()

describe('PromptLabel', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    mockUseFilteredModels.mockReturnValue({
      availableModels: [model, mockOrgAllowedModel],
      isLoadingModels: false,
    })
  })

  test('renders the pretty model name and icon with selectedModel', () => {
    mockFindModel.mockReturnValue(model)
    render(<PromptLabel modelId={model.id} />, {appPayload: getModelRepoPromptsAppPayload()})

    expect(screen.getByText(model.friendly_name)).toBeInTheDocument()
    const icon = screen.getByRole('img')
    expect(icon).toBeInTheDocument()
  })

  test('renders the model id and no icon without selectedModel', () => {
    mockFindModel.mockReturnValue(undefined)
    render(<PromptLabel modelId={model.id} />, {appPayload: getModelRepoPromptsAppPayload()})

    expect(screen.getByText(model.id)).toBeInTheDocument()
    const icon = screen.queryByRole('img')
    expect(icon).not.toBeInTheDocument()
  })
})
