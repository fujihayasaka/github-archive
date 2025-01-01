import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {
  AutofixValidationChecksOverlayContent,
  type AutofixValidationChecksOverlayContentProps,
} from '../../components/AutofixValidationChecksOverlayContent'
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
  getAutofixValidationCheck({validationType: AutofixValidationType.Tests}),
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
  getAutofixValidationCheck({
    validationType: AutofixValidationType.Tests,
    status: AutofixValidationCheckStatus.Pending,
  }),
]

const render = (props?: Partial<AutofixValidationChecksOverlayContentProps>) =>
  reactRender(
    <AutofixValidationChecksOverlayContent validationChecks={allSuccessChecks} repository={repository} {...props} />,
  )

it('renders the correct heading and text for all passing checks', () => {
  render()

  expect(screen.getByText('Validated autofix')).toBeInTheDocument()
  expect(
    screen.getByText(
      'Available autofix is passing all validation checks. It does not introduce any new vulnerabilities and is safe to commit.',
    ),
  ).toBeInTheDocument()
})

it('renders the correct heading and text for partially passing checks', () => {
  render({validationChecks: mixedStatusChecks})

  expect(screen.getByText('Partially validated autofix')).toBeInTheDocument()
  expect(
    screen.getByText(
      'Available autofix is passing some validation checks. It is recommended to review the autofix suggestion before committing.',
    ),
  ).toBeInTheDocument()
})

it('renders the correct heading and text for all failing checks', () => {
  render({validationChecks: allFailedChecks})

  expect(screen.getByText('Unvalidated autofix')).toBeInTheDocument()
  expect(
    screen.getByText(
      'Available autofix is not passing any validation checks. It is recommended to review the autofix suggestion before committing.',
    ),
  ).toBeInTheDocument()
})

it('renders the correct heading and text for all pending checks', () => {
  render({validationChecks: allPendingChecks})

  expect(screen.getByText('Unvalidated autofix')).toBeInTheDocument()
  expect(
    screen.getByText(
      'Available autofix is not passing any validation checks. It is recommended to review the autofix suggestion before committing.',
    ),
  ).toBeInTheDocument()
})

it('renders the correct number of validation check items', () => {
  render()

  expect(screen.getAllByRole('listitem')).toHaveLength(4)
})

it('renders the correct number of validation check items for mixed checks', () => {
  render({validationChecks: mixedStatusChecks})

  expect(screen.getAllByRole('listitem')).toHaveLength(3)
})

it('displays a link to the workflow run', () => {
  const workflowRunId = '98765'
  render({
    validationChecks: [
      getAutofixValidationCheck({
        validationType: AutofixValidationType.Llm,
        status: AutofixValidationCheckStatus.Success,
        workflowRunId,
      }),
    ],
  })

  const link = screen.getByText('More details')
  expect(link).toBeInTheDocument()
  expect(link).toHaveAttribute('href', `/${repository.ownerLogin}/${repository.name}/actions/runs/${workflowRunId}`)
})
