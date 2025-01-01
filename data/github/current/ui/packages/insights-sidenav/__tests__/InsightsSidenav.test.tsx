import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {InsightsSidenav} from '../InsightsSidenav'

test('Renders with items', () => {
  render(
    <InsightsSidenav
      selectedKey="dependency_insights"
      showDependencies
      showActionsUsageMetrics
      showApi
      urls={{
        dependency_insights: '#',
        actions_usage_metrics: '#',
        api: '#',
      }}
    />,
  )

  expect(screen.getByTestId('InsightsSidenav')).toBeInTheDocument()

  const dependencies = screen.getByRole('link', {name: `Dependencies`})
  expect(dependencies).toBeInTheDocument()
  // eslint-disable-next-line testing-library/no-node-access -- no way to get at it otherwise
  expect(dependencies.querySelector('svg[aria-hidden="true"]')).toBeInTheDocument()

  const actions = screen.getByRole('link', {name: `Actions Usage Metrics`})
  expect(actions).toBeInTheDocument()
  // eslint-disable-next-line testing-library/no-node-access -- no way to get at it otherwise
  expect(actions.querySelector('svg[aria-hidden="true"]')).toBeInTheDocument()

  const api = screen.getByRole('link', {name: `REST API Preview`})
  expect(api).toBeInTheDocument()
  // eslint-disable-next-line testing-library/no-node-access -- no way to get at it otherwise
  expect(api.querySelector('svg[aria-hidden="true"]')).toBeInTheDocument()
})

test('Does not render item unless prop is true', () => {
  render(
    <InsightsSidenav
      selectedKey="dependency_insights"
      showDependencies
      urls={{
        dependency_insights: '#',
        actions_usage_metrics: '#',
        api: '#',
      }}
    />,
  )

  expect(screen.getByTestId('InsightsSidenav')).toBeInTheDocument()

  const dependencies = screen.getByRole('link', {name: `Dependencies`})
  expect(dependencies).toBeInTheDocument()
  // eslint-disable-next-line testing-library/no-node-access -- no way to get at it otherwise
  expect(dependencies.querySelector('svg[aria-hidden="true"]')).toBeInTheDocument()

  expect(screen.queryByRole('link', {name: `Actions Usage Metrics`})).not.toBeInTheDocument()

  expect(screen.queryByRole('link', {name: `REST API Preview`})).not.toBeInTheDocument()
})
