import {Banner} from '@primer/react/experimental'

export interface TradeScreeningStatusBannerProps {
  isTradeRestricted: boolean
  title: string
  description: string
  className?: string
}

export function TradeScreeningStatusBanner({
  isTradeRestricted,
  title,
  description,
  className,
}: TradeScreeningStatusBannerProps) {
  if (!isTradeRestricted) {
    return null
  }
  return (
    <Banner
      variant="warning"
      title={title}
      description={<>{description}</>}
      data-testid="trade-screening-status-banner"
      className={`${className || ''}`}
    />
  )
}
