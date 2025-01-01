import {screen} from '@testing-library/react'
import {AutofixMetric, type AutofixMetricProps} from '../../components/AutofixMetric'
import {render as reactRender} from '@github-ui/react-core/test-utils'

const defaultProps: AutofixMetricProps = {
  count: 75,
  isLoading: false,
}
const render = (props?: Partial<AutofixMetricProps>) => reactRender(<AutofixMetric {...defaultProps} {...props} />)

test('Renders autofix information', () => {
  render()

  expect(screen.getByText('Copilot Autofix')).toBeInTheDocument()
  expect(screen.getByText(/Copilot Autofix will try to suggest fixes/)).toBeInTheDocument()
  expect(screen.getByRole('link')).toHaveAttribute(
    'href',
    'https://docs.github.com/en/code-security/code-scanning/managing-code-scanning-alerts/about-autofix-for-codeql-code-scanning',
  )
})
