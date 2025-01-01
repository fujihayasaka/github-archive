import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {StatCard} from '../../components/StatCard'

test('Renders a StatCard', async () => {
  render(
    <StatCard
      title="Current limit"
      delimiter="hour"
      stat="5k"
      description="This API client's current limit of requests per hour"
      data-testid="current-limit"
    />,
  )
  const statCard = screen.getByTestId('current-limit')
  expect(statCard).toBeInTheDocument()
  expect(statCard).toHaveTextContent('Current limit')
  expect(statCard).toHaveTextContent('5k / hour')
  expect(statCard).toHaveTextContent("This API client's current limit of requests per hour")
})

test('Does not render delimiter if not set', async () => {
  render(
    <StatCard
      title="Current limit"
      stat="5k"
      description="This API client's current limit of requests per hour"
      data-testid="current-limit"
    />,
  )
  const statCard = screen.getByTestId('current-limit')
  expect(statCard).toBeInTheDocument()
  expect(statCard).toHaveTextContent('Current limit')
  expect(statCard).toHaveTextContent('5k')
  expect(statCard).not.toHaveTextContent('5k / hour')
  expect(statCard).toHaveTextContent("This API client's current limit of requests per hour")
})

test('Does not render delimiter if stat is not set', async () => {
  render(
    <StatCard
      title="Current limit"
      delimiter="hour"
      description="This API client's current limit of requests per hour"
      data-testid="current-limit"
    />,
  )
  const statCard = screen.getByTestId('current-limit')
  expect(statCard).toBeInTheDocument()
  expect(statCard).toHaveTextContent('Current limit')
  expect(statCard).toHaveTextContent('N/A')
  expect(statCard).not.toHaveTextContent('/ hour')
  expect(statCard).toHaveTextContent("This API client's current limit of requests per hour")
})
