import {Banner} from '@primer/react/experimental'

export interface TradeScreeningStatusBannerProps {
  isTradeRestricted: boolean
  hideTitle?: boolean
  title: string
  description: string
  className?: string
}

export function TradeScreeningStatusBanner({
  isTradeRestricted,
  hideTitle,
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
      hideTitle={hideTitle}
      // All description text come from TradeControls::Notices and are already sanitized
      // eslint-disable-next-line react/no-danger
      description={<span dangerouslySetInnerHTML={{__html: description}} />}
      data-testid="trade-screening-status-banner"
      className={`${className || ''}`}
    />
  )
}
