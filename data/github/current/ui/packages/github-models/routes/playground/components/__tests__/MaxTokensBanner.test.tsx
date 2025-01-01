import {render, screen} from '@testing-library/react'
import type {PlaygroundRequestParameters} from '../../../../types'
import {
  mockModel,
  mockModelInputSchema,
  mockModelIntegerInputSchemaParameter,
  mockTokenUsage,
} from '../../__tests__/mocks'
import {MaxTokensBanner} from '../MaxTokensBanner'
import {mockModelState} from './mocks'

describe('MaxTokensBanner', () => {
  test('does not render when max output tokens has not been reached', () => {
    const tokenUsage = Object.assign({}, mockTokenUsage, {totalOutputTokens: 0})
    const maxTokensParam = Object.assign({}, mockModelIntegerInputSchemaParameter, {key: 'max_tokens'})
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {parameters: [maxTokensParam]})
    const model = Object.assign({}, mockModel, {max_output_tokens: 10000})
    const parameters: PlaygroundRequestParameters = {}
    const modelState = mockModelState({catalogData: model, tokenUsage, modelInputSchema, parameters})

    render(<MaxTokensBanner modelState={modelState} />)

    expect(screen.queryByTestId('max-tokens-banner')).not.toBeInTheDocument()
  })

  test('renders when max output tokens has been reached', () => {
    const tokenUsage = Object.assign({}, mockTokenUsage, {totalOutputTokens: 10001})
    const maxTokensParam = Object.assign({}, mockModelIntegerInputSchemaParameter, {key: 'max_tokens'})
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {parameters: [maxTokensParam]})
    const model = Object.assign({}, mockModel, {max_output_tokens: 10000})
    const parameters: PlaygroundRequestParameters = {}
    const modelState = mockModelState({catalogData: model, tokenUsage, modelInputSchema, parameters})

    render(<MaxTokensBanner modelState={modelState} />)

    const banner = screen.getByTestId('max-tokens-banner')
    expect(banner).toBeInTheDocument()
    expect(banner).toHaveTextContent(/You have reached the maximum tokens limit/)
  })

  test('does not render while model is replying', () => {
    const tokenUsage = Object.assign({}, mockTokenUsage, {totalOutputTokens: 10001})
    const maxTokensParam = Object.assign({}, mockModelIntegerInputSchemaParameter, {key: 'max_tokens'})
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {parameters: [maxTokensParam]})
    const model = Object.assign({}, mockModel, {max_output_tokens: 10000})
    const parameters: PlaygroundRequestParameters = {}
    const modelState = mockModelState({isLoading: true, catalogData: model, tokenUsage, modelInputSchema, parameters})

    render(<MaxTokensBanner modelState={modelState} />)

    expect(screen.queryByTestId('max-tokens-banner')).not.toBeInTheDocument()
  })
})
