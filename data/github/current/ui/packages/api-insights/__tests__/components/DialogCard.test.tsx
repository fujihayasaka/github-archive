import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {DialogCard} from '../../components/DialogCard'

test('Renders a DialogCard', async () => {
  render(
    <DialogCard
      username="monalisa"
      isOpen={false}
      title="Current limit"
      stat="5k"
      total_contributors_requests="10k"
      delimiter="hour"
      description="This API client's current limit of requests per hour"
      data-testid="current-limit"
    >
      Hello World
    </DialogCard>,
  )
  const dialogCard = screen.getByTestId('current-limit')
  expect(dialogCard).toBeInTheDocument()
  expect(dialogCard).toHaveTextContent('Current limit')
  expect(dialogCard).toHaveTextContent('5k / hour')
  expect(dialogCard).toHaveTextContent("This API client's current limit of requests per hour")
})

test('Does not render delimiter if not set', async () => {
  render(
    <DialogCard
      username="monalisa"
      isOpen={false}
      title="Current limit"
      stat="5k"
      total_contributors_requests="10k"
      description="This API client's current limit of requests per hour"
      data-testid="current-limit"
    >
      Hello World
    </DialogCard>,
  )
  const dialogCard = screen.getByTestId('current-limit')
  expect(dialogCard).toBeInTheDocument()
  expect(dialogCard).toHaveTextContent('Current limit')
  expect(dialogCard).toHaveTextContent('5k')
  expect(dialogCard).not.toHaveTextContent('5k / hour')
  expect(dialogCard).toHaveTextContent("This API client's current limit of requests per hour")
})

test('Does not render delimiter if stat is not set', async () => {
  render(
    <DialogCard
      username="monalisa"
      isOpen={false}
      title="Current limit"
      total_contributors_requests="10k"
      delimiter="hour"
      description="This API client's current limit of requests per hour"
      data-testid="current-limit"
    >
      Hello World
    </DialogCard>,
  )
  const dialogCard = screen.getByTestId('current-limit')
  expect(dialogCard).toBeInTheDocument()
  expect(dialogCard).toHaveTextContent('Current limit')
  expect(dialogCard).toHaveTextContent('N/A')
  expect(dialogCard).not.toHaveTextContent('/ hour')
  expect(dialogCard).toHaveTextContent("This API client's current limit of requests per hour")
})
