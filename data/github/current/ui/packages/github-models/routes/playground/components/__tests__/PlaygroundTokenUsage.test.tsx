import {render, within} from '@testing-library/react'
import type {PlaygroundMessage, PlaygroundRequestParameters, TokenUsage} from '../../../../types'
import {PlaygroundTokenUsage} from '../PlaygroundTokenUsage'
import {mockModelState} from './mocks'
import {mockModel, mockModelInputSchema, mockModelIntegerInputSchemaParameter} from '../../__tests__/mocks'

describe('PlaygroundTokenUsage', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders with token data', () => {
    const tokenUsage: TokenUsage = {
      lastMessageInputTokens: 1000,
      totalInputTokens: 2500,
      lastMessageOutputTokens: 3000,
      totalOutputTokens: 4123,
    }
    const model = Object.assign({}, mockModel, {friendly_name: 'My Fancy Model'})
    const modelState = mockModelState({catalogData: model, tokenUsage})

    const {container} = render(<PlaygroundTokenUsage modelState={modelState} border />)

    expect(within(container).getByTestId('model-name')).toHaveTextContent('My Fancy Model')
    expect(
      within(within(container).getByTestId('playground-usage-input-tokens')).getByText('Most recent message: 1,000'),
    ).toBeInTheDocument()
    expect(
      within(within(container).getByTestId('playground-usage-input-tokens')).getByText('Total: 2,500'),
    ).toBeInTheDocument()
    expect(
      within(within(container).getByTestId('playground-usage-output-tokens')).getByText('Most recent message: 3,000'),
    ).toBeInTheDocument()
    expect(
      within(within(container).getByTestId('playground-usage-output-tokens')).getByText('Total: 4,123'),
    ).toBeInTheDocument()
  })

  test('renders max input and output tokens', () => {
    const model = Object.assign({}, mockModel, {max_output_tokens: 123456, max_input_tokens: 789000})
    const modelState = mockModelState({catalogData: model})

    const {container} = render(<PlaygroundTokenUsage modelState={modelState} />)

    expect(within(container).getByTestId('max-input-tokens')).toHaveTextContent('Limit: 789,000')
    expect(within(container).getByTestId('max-output-tokens')).toHaveTextContent('Limit: 123,456')
  })

  test('renders when max output tokens parameter exists', () => {
    const model = Object.assign({}, mockModel, {max_output_tokens: 123456})
    const maxTokensParam = Object.assign({}, mockModelIntegerInputSchemaParameter, {key: 'max_tokens'})
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {parameters: [maxTokensParam]})
    const parameters: PlaygroundRequestParameters = {max_tokens: 3000}
    const modelState = mockModelState({catalogData: model, modelInputSchema, parameters})

    const {container} = render(<PlaygroundTokenUsage modelState={modelState} />)

    expect(within(container).getByTestId('max-output-tokens')).toHaveTextContent('Limit: 123,456 · 3,000 for parameter')
  })

  test('renders the timestamp for the latest user message', () => {
    const messages: PlaygroundMessage[] = [
      {role: 'user', timestamp: new Date('1999-01-01T10:18:15Z'), message: 'foo'},
      {role: 'user', timestamp: new Date('1999-01-02T10:19:15Z'), message: 'baz'},
      {role: 'assistant', timestamp: new Date('1999-01-03T10:20:15Z'), message: 'bar'},
    ]
    const modelState = mockModelState({messages})

    const {container} = render(<PlaygroundTokenUsage modelState={modelState} />)

    expect(within(container).getByTestId('latest-user-message-time')).toHaveTextContent('Jan 2, 1999')
  })
})
