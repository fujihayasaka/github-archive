import {within} from '@testing-library/react'
import {CreatePromptFileButton} from '../CreatePromptFileButton'
import {render} from '@github-ui/react-core/test-utils'
import {mockModelState} from './mocks'
import {repoModelPlaygroundPath, repoPromptNewPath} from '@github-ui/paths'
import {mockModel} from '../../__tests__/mocks'

const mockNavigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => mockNavigateFn,
  }
})

describe('CreatePromptFileButton', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  const repository = {
    name: 'repo-name',
    ownerLogin: 'owner-login',
  }

  test('renders the Create prompt.yml file button', () => {
    const {container} = render(<CreatePromptFileButton modelState={mockModelState()} repository={repository} />)
    expect(within(container).getByRole('button', {name: 'Create prompt.yml file'})).toBeInTheDocument()
  })

  test('navigates to the prompt/new page when the Create prompt.yml file button is clicked', async () => {
    const model = {...mockModelState(), parameters: {max_tokens: 1234}}
    const {container, user} = render(<CreatePromptFileButton modelState={model} repository={repository} />, {
      pathname: repoModelPlaygroundPath(repository, mockModel),
    })
    const button = within(container).getByRole('button', {name: 'Create prompt.yml file'})
    expect(button).toBeInTheDocument()

    await user.click(button)

    expect(mockNavigateFn).toHaveBeenCalledWith(repoPromptNewPath(repository), {
      state: {
        model: model.catalogData.original_name,
        params: model.parameters,
        systemPrompt: model.systemPrompt,
      },
    })
  })
})
