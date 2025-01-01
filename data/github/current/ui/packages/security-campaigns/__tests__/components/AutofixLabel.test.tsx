import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {AutofixLabel, type AutofixLabelProps} from '../../components/AutofixLabel'
import {AutofixValidationCheckStatus, AutofixValidationType} from '../../types/autofix-validation-check'
import {getAutofixValidationCheck} from '../../test-utils/mock-data'

const defaultProps: AutofixLabelProps = {
  validationChecks: undefined,
}

const render = (props?: Partial<AutofixLabelProps>) => reactRender(<AutofixLabel {...defaultProps} {...props} />)

test('renders default "Autofix" label when validationChecks is undefined', () => {
  render()

  expect(screen.getByText('Autofix')).toBeInTheDocument()
})

test('renders default "Autofix" label when validationChecks is empty array', () => {
  render({validationChecks: []})

  expect(screen.getByText('Autofix')).toBeInTheDocument()
})

test('renders default "Autofix" label when some validationChecks are not successful', () => {
  render({
    validationChecks: [
      {
        validationType: AutofixValidationType.CodeQL,
        status: AutofixValidationCheckStatus.Success,
        workflowRunId: '123',
      },
      {
        validationType: AutofixValidationType.Tests,
        status: AutofixValidationCheckStatus.Failed,
        workflowRunId: '456',
      },
    ],
  })

  expect(screen.getByText('Autofix')).toBeInTheDocument()
})

test('renders "Validated autofix" label when all validationChecks are successful', () => {
  render({
    validationChecks: [
      getAutofixValidationCheck({
        validationType: AutofixValidationType.CodeQL,
        status: AutofixValidationCheckStatus.Success,
      }),
      getAutofixValidationCheck({
        validationType: AutofixValidationType.Tests,
        status: AutofixValidationCheckStatus.Success,
      }),
    ],
  })

  expect(screen.getByText('Validated autofix')).toBeInTheDocument()
})

test('renders "Validated autofix" label with single successful validation check', () => {
  render({
    validationChecks: [
      getAutofixValidationCheck({
        validationType: AutofixValidationType.Llm,
        status: AutofixValidationCheckStatus.Success,
      }),
    ],
  })

  expect(screen.getByText('Validated autofix')).toBeInTheDocument()
})
