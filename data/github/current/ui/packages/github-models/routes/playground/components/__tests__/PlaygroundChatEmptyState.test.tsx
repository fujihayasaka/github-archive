import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import PlaygroundChatEmptyState from '../PlaygroundChatEmptyState'
import {mockModelState} from './mocks'
import {mockModelInputSchema} from '../../__tests__/mocks'

const submitMessage = jest.fn()

describe('PlaygroundChatEmptyState', () => {
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
})
