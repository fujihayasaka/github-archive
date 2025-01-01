import {screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotMetricsInsightsCatalog} from '../routes/CopilotMetricsInsightsCatalog'

function getCopilotMetricsCatalogRoutePayload(testParams = {}) {
  return Object.assign(
    {
      dashboards: [
        {
          name: 'Copilot user onboarding',
          description: 'Tracks engagement to evaluate onboarding effectiveness and pinpoint areas for improvement.',
          category: 'Category',
          path: '/test/copilot-user-onboarding',
        },
        {
          name: 'Copilot code completions acceptance rate',
          description: "Tracks the percentage of Copilot's code completions suggestions.",
          category: 'Category',
          path: '/test/copilot-code-completions-acceptance-rate',
        },
        {
          name: 'Copilot generated code acceptance rate',
          description: 'Measures the rate at which generated code suggestions are accepted across the organization.',
          category: 'Category',
          path: '/test/copilot-generated-code-acceptance-rate',
        },
      ],
    },
    testParams,
  )
}

test('renders the Copilot Metrics Insights Catalog with all dashboards having proper text', () => {
  const routePayload = getCopilotMetricsCatalogRoutePayload()
  render(<CopilotMetricsInsightsCatalog />, {routePayload})

  const listView = screen.getByTestId('insights-catalog-list-view')
  expect(listView).toBeInTheDocument()
  expect(screen.getByRole('heading', {name: 'Metrics'})).toBeInTheDocument()
  expect(screen.getByText('3 Metrics')).toBeInTheDocument()

  const listItems = within(listView).getAllByRole('listitem')
  expect(listItems).toHaveLength(3)

  // for each list item, we expect to see the dashboard name, description, and category that is provided in the route payload
  for (const [index, listItem] of listItems.entries()) {
    const dashboard = routePayload.dashboards[index]
    expect(dashboard).toBeDefined()
    expect(listItem).toHaveTextContent(dashboard!.name)
    expect(listItem).toHaveTextContent(dashboard!.description)
    expect(listItem).toHaveTextContent(dashboard!.category)
  }
})

test('dashboard entries link to the correct path', async () => {
  const routePayload = getCopilotMetricsCatalogRoutePayload()
  render(<CopilotMetricsInsightsCatalog />, {routePayload})

  const listView = screen.getByTestId('insights-catalog-list-view')
  const listItems = within(listView).getAllByRole('listitem')

  for (const [index, listItem] of listItems.entries()) {
    const dashboard = routePayload.dashboards[index]
    expect(dashboard).toBeDefined()

    const listItemLink = within(listItem).getByRole('link')
    expect(listItemLink).toHaveAttribute('href', dashboard!.path)
  }
})

test('handles single dashboard entry correctly', () => {
  const singleDashboardPayload = getCopilotMetricsCatalogRoutePayload({
    dashboards: [
      {
        name: 'Copilot user onboarding',
        description: 'Tracks engagement to evaluate onboarding effectiveness.',
        category: 'Copilot',
        path: '/orgs/github/insights/metrics/copilot-user-onboarding',
      },
    ],
  })

  render(<CopilotMetricsInsightsCatalog />, {routePayload: singleDashboardPayload})

  expect(screen.getByText('1 Metric')).toBeInTheDocument()
  expect(screen.getAllByRole('listitem')).toHaveLength(1)
})

test('render multiple dashboard entries', () => {
  const manyDashboardsPayload = getCopilotMetricsCatalogRoutePayload({
    dashboards: Array(10)
      .fill(0)
      .map((_, i) => ({
        name: `Dashboard ${i + 1}`,
        description: `Description ${i + 1}`,
        category: 'Category',
        path: `/path/${i + 1}`,
      })),
  })

  render(<CopilotMetricsInsightsCatalog />, {routePayload: manyDashboardsPayload})

  expect(screen.getByText('10 Metrics')).toBeInTheDocument()
  expect(screen.getAllByRole('listitem')).toHaveLength(10)
})
