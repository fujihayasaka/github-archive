import {screen} from '@testing-library/react'
import {AutofixSupportedMetric, type AutofixSupportedMetricProps} from '../../components/AutofixSupportedMetric'
import {render as reactRender} from '@github-ui/react-core/test-utils'

const defaultProps: AutofixSupportedMetricProps = {
  isDraft: false,
  count: 0,
  isLoading: false,
}
const render = (props?: Partial<AutofixSupportedMetricProps>) =>
  reactRender(<AutofixSupportedMetric {...defaultProps} {...props} />)

test('Renders autofix information', () => {
  render()

  expect(screen.getByText('Copilot Autofix')).toBeInTheDocument()
  expect(screen.getByText(/Copilot Autofix will try to suggest fixes/)).toBeInTheDocument()
  expect(screen.getByRole('link')).toHaveAttribute(
    'href',
    'https://docs.github.com/en/code-security/code-scanning/managing-code-scanning-alerts/about-autofix-for-codeql-code-scanning',
  )
})
