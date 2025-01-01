import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockShowModelPayload} from '../../../../show/components/__tests__/mocks'
import {ModelLegalTerms, productTermsLink, privacyStatementLink} from '../ModelLegalTerms'

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
  }
})

describe('ModelLegalTerms', () => {
  test('renders for authenticated viewer', async () => {
    const payload = mockShowModelPayload({isLoggedIn: true})

    const {container, user} = render(<ModelLegalTerms modelName="Some model" />, {routePayload: payload})

    const legalTermsEl = within(container).getByTestId('legal-terms')
    expect(legalTermsEl).toBeInTheDocument()
    const feedbackButton = within(legalTermsEl).getByRole('button', {name: 'Share feedback'})
    expect(feedbackButton).toBeInTheDocument()
    expect(within(legalTermsEl).getByRole('link', {name: 'Product Terms'})).toHaveAttribute('href', productTermsLink)
    expect(within(legalTermsEl).getByRole('link', {name: 'Privacy Statement'})).toHaveAttribute(
      'href',
      privacyStatementLink,
    )
    expect(within(container).queryByRole('dialog', {name: 'Provide feedback'})).not.toBeInTheDocument()

    await user.click(feedbackButton)

    expect(within(container).getByRole('dialog', {name: 'Provide feedback'})).toBeInTheDocument()
    expect(navigateFn).not.toHaveBeenCalled()
  })

  test('renders for anonymous viewer', async () => {
    const payload = mockShowModelPayload({isLoggedIn: false})
    const currentPath = '/the/page/we/are/on'

    const {container, user} = render(<ModelLegalTerms modelName="Some model" />, {
      pathname: currentPath,
      routePayload: payload,
    })

    const legalTermsEl = within(container).getByTestId('legal-terms')
    expect(legalTermsEl).toBeInTheDocument()
    const feedbackButton = within(legalTermsEl).getByRole('button', {name: 'Share feedback'})
    expect(feedbackButton).toBeInTheDocument()
    expect(within(legalTermsEl).getByRole('link', {name: 'Product Terms'})).toHaveAttribute('href', productTermsLink)
    expect(within(legalTermsEl).getByRole('link', {name: 'Privacy Statement'})).toHaveAttribute(
      'href',
      privacyStatementLink,
    )
    expect(within(container).queryByRole('dialog', {name: 'Provide feedback'})).not.toBeInTheDocument()

    await user.click(feedbackButton)

    expect(within(container).queryByRole('dialog', {name: 'Provide feedback'})).not.toBeInTheDocument()
    expect(navigateFn).toHaveBeenCalledTimes(1)
    const navigatedTo = navigateFn.mock.lastCall?.[0] as string
    expect(navigatedTo).toEqual(`/login?return_to=${encodeURIComponent(currentPath)}`)
  })
})
