import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {
  AutofixValidationChecksButton,
  type AutofixValidationChecksButtonProps,
} from '../../components/AutofixValidationChecksButton'
import {createRepository, getAutofixValidationCheck} from '../../test-utils/mock-data'
import {
  AutofixValidationCheckStatus,
  AutofixValidationType,
  type AutofixValidationCheck,
} from '../../types/autofix-validation-check'

const repository = createRepository()

const allSuccessChecks: AutofixValidationCheck[] = [
  getAutofixValidationCheck({validationType: AutofixValidationType.Llm}),
  getAutofixValidationCheck({validationType: AutofixValidationType.CodeQL}),
  getAutofixValidationCheck({validationType: AutofixValidationType.Linter}),
]

const mixedStatusChecks: AutofixValidationCheck[] = [
  getAutofixValidationCheck({validationType: AutofixValidationType.Llm, status: AutofixValidationCheckStatus.Success}),
  getAutofixValidationCheck({
    validationType: AutofixValidationType.CodeQL,
    status: AutofixValidationCheckStatus.Failed,
  }),
  getAutofixValidationCheck({
    validationType: AutofixValidationType.Linter,
    status: AutofixValidationCheckStatus.Pending,
  }),
]

const allFailedChecks: AutofixValidationCheck[] = [
  getAutofixValidationCheck({validationType: AutofixValidationType.Llm, status: AutofixValidationCheckStatus.Failed}),
  getAutofixValidationCheck({
    validationType: AutofixValidationType.CodeQL,
    status: AutofixValidationCheckStatus.Failed,
  }),
]

const allPendingChecks: AutofixValidationCheck[] = [
  getAutofixValidationCheck({validationType: AutofixValidationType.Llm, status: AutofixValidationCheckStatus.Pending}),
  getAutofixValidationCheck({
    validationType: AutofixValidationType.CodeQL,
    status: AutofixValidationCheckStatus.Pending,
  }),
]

const render = (props?: Partial<AutofixValidationChecksButtonProps>) =>
  reactRender(<AutofixValidationChecksButton validationChecks={allSuccessChecks} repository={repository} {...props} />)

it('renders button with correct count for all success checks', () => {
  render()

  const button = screen.getByRole('button')
  expect(button).toHaveTextContent('3/3')
})

it('renders button with correct count for mixed status checks', () => {
  render({validationChecks: mixedStatusChecks})

  const button = screen.getByRole('button')
  expect(button).toHaveTextContent('1/3')
})

it('renders button with correct count for all failed checks', () => {
  render({validationChecks: allFailedChecks})

  const button = screen.getByRole('button')
  expect(button).toHaveTextContent('0/2')
})

it('renders button with correct count for all pending checks', () => {
  render({validationChecks: allPendingChecks})

  const button = screen.getByRole('button')
  expect(button).toHaveTextContent('0/2')
})

it('does not render anything when validation checks are empty', () => {
  render({validationChecks: []})

  expect(screen.queryByRole('button')).not.toBeInTheDocument()
})

it('opens overlay when button is clicked', async () => {
  const {user} = render()

  const button = screen.getByRole('button')
  await user.click(button)

  // The AnchoredOverlay should be open and display the ValidationChecksOverlayContent
  expect(screen.getByText('Validated autofix')).toBeInTheDocument()
})

it('closes overlay when clicked outside', async () => {
  const {user} = render()

  // Open the overlay
  const button = screen.getByRole('button')
  await user.click(button)

  // Verify overlay is open
  expect(screen.getByText('Validated autofix')).toBeInTheDocument()

  // Simulate clicking outside the overlay
  await user.click(document.body)

  // The overlay content should no longer be visible
  expect(screen.queryByText('Validated autofix')).not.toBeInTheDocument()
})
