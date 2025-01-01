import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import PlaygroundChatEmptyState from '../PlaygroundChatEmptyState'
import {mockModelState} from './mocks'
import {mockModel, mockModelInputSchema} from '../../__tests__/mocks'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlag = jest.mocked(useFeatureFlag)

const submitMessage = jest.fn()

describe('PlaygroundChatEmptyState', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders without sample inputs', () => {
    const modelInputSchema = Object.assign({}, mockModelInputSchema)
    modelInputSchema.sampleInputs = []
    const modelState = mockModelState({modelInputSchema})

    const {container} = render(<PlaygroundChatEmptyState model={modelState} submitMessage={submitMessage} />)

    expect(
      within(container).getByRole('heading', {name: modelState.catalogData.friendly_name, level: 3}),
    ).toBeInTheDocument()
    expect(within(container).getByRole('paragraph')).toHaveTextContent(modelState.catalogData.summary || '')
    expect(within(container).queryByTestId('sample-inputs')).not.toBeInTheDocument()
    expect(submitMessage).not.toHaveBeenCalled()
  })

  test('renders with sample inputs', async () => {
    const modelInputSchema = Object.assign({}, mockModelInputSchema)
    const sampleMessage1 = 'sample message the first'
    const sampleMessage2 = 'The second sample message.'
    modelInputSchema.sampleInputs = [{messages: [{content: sampleMessage1}]}, {messages: [{content: sampleMessage2}]}]
    const modelState = mockModelState({modelInputSchema})

    const {container, user} = render(<PlaygroundChatEmptyState model={modelState} submitMessage={submitMessage} />)

    expect(
      within(container).getByRole('heading', {name: modelState.catalogData.friendly_name, level: 3}),
    ).toBeInTheDocument()
    expect(within(container).getByRole('paragraph')).toHaveTextContent(modelState.catalogData.summary || '')
    const sampleInputsEl = within(container).getByTestId('sample-inputs')
    expect(sampleInputsEl).toBeInTheDocument()
    const sampleMessage1Card = within(sampleInputsEl).getByText(sampleMessage1)
    expect(sampleMessage1Card).toBeInTheDocument()
    expect(within(sampleInputsEl).getByText(sampleMessage2)).toBeInTheDocument()
    expect(submitMessage).not.toHaveBeenCalled()

    await user.click(sampleMessage1Card)

    expect(submitMessage).toHaveBeenCalledWith(sampleMessage1)
  })

  test('renders with a warning banner for DeepSeek-R1 when feature enabled', () => {
    mockUseFeatureFlag.mockImplementation(flag => flag === 'github_models_deepseek_r1_unstable')

    const mockDeepSeekModel = {...mockModel, name: 'DeepSeek-R1'}
    const modelState = mockModelState({catalogData: mockDeepSeekModel})

    const {container} = render(<PlaygroundChatEmptyState model={modelState} submitMessage={submitMessage} />)

    expect(within(container).getByTestId('unstable-model-warning-banner')).toBeInTheDocument()
  })

  test('does not render with a warning banner for other models when feature enabled', () => {
    mockUseFeatureFlag.mockImplementation(flag => flag === 'github_models_deepseek_r1_unstable')

    const mockDeepSeekModel = {...mockModel, name: 'Phi-4-multimodal-instruct'}
    const modelState = mockModelState({catalogData: mockDeepSeekModel})

    const {container} = render(<PlaygroundChatEmptyState model={modelState} submitMessage={submitMessage} />)

    expect(within(container).queryByTestId('unstable-model-warning-banner')).not.toBeInTheDocument()
  })

  test('does not render with a warning banner for DeepSeek-R1 when feature disabled', () => {
    mockUseFeatureFlag.mockReturnValue(false)

    const mockDeepSeekModel = {...mockModel, name: 'DeepSeek-R1'}
    const modelState = mockModelState({catalogData: mockDeepSeekModel})

    const {container} = render(<PlaygroundChatEmptyState model={modelState} submitMessage={submitMessage} />)

    expect(within(container).queryByTestId('unstable-model-warning-banner')).not.toBeInTheDocument()
  })
})
