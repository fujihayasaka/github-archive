import type {SafeHTMLString} from '@github-ui/safe-html'
import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockShowModelPayload} from './mocks'
import {Evaluation} from '../Evaluation'

describe('Evaluation', () => {
  test('renders when the model has evaluation content', () => {
    const payload = mockShowModelPayload({modelEvaluation: '<p>We trained this in-house</p>' as SafeHTMLString})

    const {container} = render(<Evaluation />, {routePayload: payload})

    const evaluationContentEl = within(container).getByTestId('evaluation-content')
    expect(evaluationContentEl).toBeInTheDocument()
    expect(within(evaluationContentEl).getByRole('paragraph')).toHaveTextContent('We trained this in-house')
  })

  test('renders nothing when the model does not have evaluation content', () => {
    const payload = mockShowModelPayload({modelEvaluation: undefined})
    const {container} = render(<Evaluation />, {routePayload: payload})
    expect(within(container).queryByTestId('evaluation-content')).not.toBeInTheDocument()
  })

  test('renders nothing when the model has a blank string for its evaluation', () => {
    const payload = mockShowModelPayload({modelEvaluation: '' as SafeHTMLString})
    const {container} = render(<Evaluation />, {routePayload: payload})
    expect(within(container).queryByTestId('evaluation-content')).not.toBeInTheDocument()
  })
})
