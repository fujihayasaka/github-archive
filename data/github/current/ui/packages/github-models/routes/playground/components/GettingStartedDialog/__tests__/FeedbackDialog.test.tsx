import {useRef} from 'react'
import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {Feedback} from '../types'
import {mockShowModelPayload} from '../../../../show/components/__tests__/mocks'
import {mockModel} from '../../../__tests__/mocks'
import {FeedbackDialog, type FeedbackDialogProps} from '../FeedbackDialog'

const setIsFeedbackDialogOpen = jest.fn()
const mockVerifiedFetchJSON = jest.fn()

jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('FeedbackDialog', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  test('does not render dialog when closed', () => {
    const {container} = render(
      <TestComponent modelName="Some model" isFeedbackDialogOpen={false} isNegativePreSelected={false} />,
      {routePayload: mockShowModelPayload()},
    )

    expect(within(container).queryByRole('dialog', {name: 'Provide feedback'})).not.toBeInTheDocument()
    expect(setIsFeedbackDialogOpen).not.toHaveBeenCalled()
    expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()
  })

  test('renders dialog when open and allows closing', async () => {
    const payload = mockShowModelPayload({canProvideAdditionalFeedback: false})

    const {container, user} = render(
      <TestComponent modelName="Some model" isFeedbackDialogOpen isNegativePreSelected={false} />,
      {routePayload: payload},
    )

    const feedbackDialog = within(container).getByRole('dialog', {name: 'Provide feedback'})
    expect(feedbackDialog).toBeInTheDocument()
    const closeButton = within(feedbackDialog).getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    expect(within(feedbackDialog).getByRole('button', {name: 'Positive'})).toBeInTheDocument()
    expect(within(feedbackDialog).getByRole('button', {name: 'Negative'})).toBeInTheDocument()
    expect(
      within(feedbackDialog).getByRole('heading', {name: 'How has your experience been with GitHub Models?'}),
    ).toBeInTheDocument()
    expect(within(feedbackDialog).queryByRole('button', {name: 'Submit feedback'})).not.toBeInTheDocument()
    expect(within(feedbackDialog).queryByRole('textbox', {name: 'Additional information'})).not.toBeInTheDocument()
    expect(
      within(feedbackDialog).queryByRole('checkbox', {
        name: 'Allow GitHub to follow up about this feedback using the primary email address on your account.',
      }),
    ).not.toBeInTheDocument()
    expect(setIsFeedbackDialogOpen).not.toHaveBeenCalled()

    await user.click(closeButton)

    expect(setIsFeedbackDialogOpen).toHaveBeenCalledTimes(1)
    expect(setIsFeedbackDialogOpen).toHaveBeenCalledWith(false)
    expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()
  })

  test('renders dialog with negative feedback selected and allows submitting negative feedback', async () => {
    const payload = mockShowModelPayload({model: mockModel})

    const {container, user} = render(
      <TestComponent modelName="Some model" isFeedbackDialogOpen isNegativePreSelected />,
      {routePayload: payload},
    )

    const feedbackDialog = within(container).getByRole('dialog', {name: 'Provide feedback'})
    expect(feedbackDialog).toBeInTheDocument()
    expect(within(feedbackDialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(within(feedbackDialog).queryByRole('button', {name: 'Positive'})).not.toBeInTheDocument()
    expect(within(feedbackDialog).queryByRole('button', {name: 'Negative'})).not.toBeInTheDocument()
    const reasonsFieldset = within(feedbackDialog).getByRole('group', {name: 'This response is...'})
    expect(reasonsFieldset).toBeInTheDocument()
    expect(within(reasonsFieldset).getByRole('checkbox', {name: 'Harmful or unsafe'})).toBeInTheDocument()
    const notTrueCheckbox = within(reasonsFieldset).getByRole('checkbox', {name: 'Not true'})
    expect(notTrueCheckbox).toBeInTheDocument()
    expect(within(reasonsFieldset).getByRole('checkbox', {name: 'Not helpful'})).toBeInTheDocument()
    expect(within(reasonsFieldset).getByRole('checkbox', {name: 'Other'})).toBeInTheDocument()
    const submitButton = within(feedbackDialog).getByRole('button', {name: 'Submit feedback'})
    expect(submitButton).toBeInTheDocument()
    expect(
      within(feedbackDialog).queryByRole('heading', {name: 'How has your experience been with GitHub Models?'}),
    ).not.toBeInTheDocument()
    expect(setIsFeedbackDialogOpen).not.toHaveBeenCalled()
    expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()

    mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: jest.fn()})

    await user.click(notTrueCheckbox)
    await user.click(submitButton)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/marketplace/models/${mockModel.registry}/${mockModel.name}/feedback`,
      {
        method: 'POST',
        body: {
          feedback: {
            contactConsent: false,
            feedbackText: '',
            model: 'Some model',
            reasons: ['not true'],
            satisfaction: Feedback.NEGATIVE,
          },
        },
      },
    )
  })

  test('renders additional feedback text field when allowed', async () => {
    const payload = mockShowModelPayload({canProvideAdditionalFeedback: true})

    const {container, user} = render(<TestComponent modelName="Some model" isFeedbackDialogOpen />, {
      routePayload: payload,
    })

    const feedbackDialog = within(container).getByRole('dialog', {name: 'Provide feedback'})
    expect(feedbackDialog).toBeInTheDocument()
    expect(within(feedbackDialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(within(feedbackDialog).getByRole('button', {name: 'Positive'})).toBeInTheDocument()
    expect(within(feedbackDialog).getByRole('button', {name: 'Negative'})).toBeInTheDocument()
    expect(
      within(feedbackDialog).getByRole('heading', {name: 'How has your experience been with GitHub Models?'}),
    ).toBeInTheDocument()
    const additionalFeedbackInput = within(feedbackDialog).getByRole('textbox', {name: 'Additional information'})
    expect(additionalFeedbackInput).toBeInTheDocument()
    const submitButton = within(feedbackDialog).getByRole('button', {name: 'Submit feedback'})
    expect(submitButton).toBeInTheDocument()
    const contactCheckbox = within(feedbackDialog).getByRole('checkbox', {
      name: 'Allow GitHub to follow up about this feedback using the primary email address on your account.',
    })
    expect(contactCheckbox).toBeInTheDocument()
    expect(setIsFeedbackDialogOpen).not.toHaveBeenCalled()
    expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()

    await user.type(additionalFeedbackInput, 'my thoughts')
    await user.click(contactCheckbox)

    mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: jest.fn()})

    await user.click(submitButton)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/marketplace/models/${mockModel.registry}/${mockModel.name}/feedback`,
      {
        method: 'POST',
        body: {
          feedback: {
            contactConsent: true,
            feedbackText: 'my thoughts',
            model: 'Some model',
            reasons: [],
            satisfaction: Feedback.UNKNOWN,
          },
        },
      },
    )
  })
})

function TestComponent(props: Omit<FeedbackDialogProps, 'setIsFeedbackDialogOpen' | 'returnFocusRef'>) {
  const returnFocusRef = useRef(null)
  return (
    <>
      <button ref={returnFocusRef}>toggle dialog</button>
      <FeedbackDialog {...props} setIsFeedbackDialogOpen={setIsFeedbackDialogOpen} returnFocusRef={returnFocusRef} />
    </>
  )
}
