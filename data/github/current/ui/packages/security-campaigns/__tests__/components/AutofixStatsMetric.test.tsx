import {screen} from '@testing-library/react'
import {AutofixStatsMetric, type AutofixStatsMetricProps} from '../../components/AutofixStatsMetric'
import {render as reactRender} from '@github-ui/react-core/test-utils'

const defaultProps: AutofixStatsMetricProps = {
  generatedCount: 210,
  appliedCount: 50,
}

const render = (props?: Partial<AutofixStatsMetricProps>) =>
  reactRender(<AutofixStatsMetric {...defaultProps} {...props} />)

test('Renders stats', () => {
  render()

  expect(screen.getByText('Fixed alerts using Copilot Autofix')).toBeInTheDocument()
  expect(screen.getByText(`${defaultProps.appliedCount}`)).toBeInTheDocument()
  expect(screen.getByText(`${defaultProps.generatedCount}`)).toBeInTheDocument()
  expect(
    screen.getByText(
      /Merged pull requests with Copilot Autofix in all campaigns using at least 50% of the suggested code./,
    ),
  ).toBeInTheDocument()
})
