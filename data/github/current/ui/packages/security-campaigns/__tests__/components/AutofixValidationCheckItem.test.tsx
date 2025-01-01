import {render as reactRender, screen} from '@testing-library/react'
import {
  AutofixValidationCheckItem,
  type AutofixValidationCheckItemProps,
} from '../../components/AutofixValidationCheckItem'
import {getAutofixValidationCheck} from '../../test-utils/mock-data'
import {AutofixValidationCheckStatus, AutofixValidationType} from '../../types/autofix-validation-check'

const defaultProps: AutofixValidationCheckItemProps = {
  validationCheck: getAutofixValidationCheck(),
}

const render = (props?: Partial<AutofixValidationCheckItemProps>) => {
  return reactRender(<AutofixValidationCheckItem {...defaultProps} {...props} />)
}

it('renders successfully', () => {
  render()

  const container = screen.getByText('Passing LLM evaluation')
  expect(container).toBeInTheDocument()
})

it('renders all combinations without errors', () => {
  // Test all combinations
  const statuses = Object.values(AutofixValidationCheckStatus)
  const types = Object.values(AutofixValidationType)

  for (const status of statuses) {
    for (const validationType of types) {
      const {unmount} = render({
        validationCheck: getAutofixValidationCheck({
          status,
          validationType,
        }),
      })

      // Component should render something (not empty)
      const content = screen.getByText(/./i)
      expect(content).toBeInTheDocument()

      unmount()
    }
  }
})

it('renders unknown status and type without crashing', () => {
  render({
    validationCheck: getAutofixValidationCheck({
      status: 'unknown' as AutofixValidationCheckStatus,
      validationType: 'unknown' as AutofixValidationType,
    }),
  })

  expect(document.body).toBeInTheDocument()
})
