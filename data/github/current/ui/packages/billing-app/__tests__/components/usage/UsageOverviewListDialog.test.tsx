import {render} from '@github-ui/react-core/test-utils'
import {act, screen} from '@testing-library/react'
import {UsageOverviewListDialog} from '../../../components/usage'

jest.mock('@github-ui/ssr-utils', () => ({
  get ssrSafeLocation() {
    return jest.fn().mockImplementation(() => {
      return {origin: 'https://github.localhost', pathname: '/enterprises/github-inc/billing'}
    })()
  },
}))

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: () => {
    return {business: 'github-inc'}
  },
}))

describe('UsageOverviewListDialog', () => {
  test('Opens dialog when more details button is clicked', async () => {
    const usageMap = {Enterprise: 100}
    render(<UsageOverviewListDialog totalUsage={200} usageMap={usageMap} />)

    await expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    await act(async () => {
      screen.getByText('More details').click()
    })
    await expect(screen.getByRole('dialog')).toBeVisible()
    expect(screen.getByTestId('total-usage')).toHaveTextContent('$200.00')
    const listItem = screen.getByTestId('usage-selection-Enterprise')
    expect(listItem.childNodes[0]?.textContent).toBe('Enterprise')
    expect(listItem.childNodes[1]?.textContent).toBe('$100.00')
  })
})
