import type {TradeScreeningStatusBannerProps} from '../TradeScreeningStatusBanner'

export function getTradeScreeningStatusBannerProps(): TradeScreeningStatusBannerProps {
  return {
    isTradeRestricted: true,
    title: "You can't proceed with your payment",
    description: 'There appears to be an issue with the billing information',
  }
}
