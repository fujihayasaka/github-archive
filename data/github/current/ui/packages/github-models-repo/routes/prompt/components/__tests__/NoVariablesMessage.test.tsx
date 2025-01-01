import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockModel} from '../../../../test-utils/mock-data'
import {NoVariablesMessage} from '../NoVariablesMessage'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('NoVariablesMessage', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders when the model does not support a system prompt', async () => {
    const model = mockModel()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => ({modelInputSchema: {capabilities: {systemPrompt: false}}}),
    })

    render(<NoVariablesMessage model={model} />)

    expect(await screen.findByRole('heading', {name: 'No variables'})).toBeInTheDocument()
    expect(screen.getByRole('paragraph')).toHaveTextContent(
      'You can add variables to the user prompt using the {{variable_name}} syntax.',
    )
  })

  it('renders when the model supports a system prompt', async () => {
    const model = mockModel()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => ({modelInputSchema: {capabilities: {systemPrompt: true}}}),
    })

    render(<NoVariablesMessage model={model} />)

    expect(await screen.findByRole('heading', {name: 'No variables'})).toBeInTheDocument()
    expect(screen.getByRole('paragraph')).toHaveTextContent(
      'You can add variables to the user and system prompts using the {{variable_name}} syntax.',
    )
  })
})
