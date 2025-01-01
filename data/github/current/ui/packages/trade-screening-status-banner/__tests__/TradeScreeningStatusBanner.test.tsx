import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {TradeScreeningStatusBanner} from '../TradeScreeningStatusBanner'
import {getTradeScreeningStatusBannerProps} from '../test-utils/mock-data'

test('Renders the TradeScreeningStatusBanner', () => {
  const props = getTradeScreeningStatusBannerProps()
  render(<TradeScreeningStatusBanner {...props} />)
  expect(screen.getByTestId('trade-screening-status-banner')).toBeInTheDocument()
})
