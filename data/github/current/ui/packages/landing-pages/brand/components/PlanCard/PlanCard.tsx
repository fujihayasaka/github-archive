import {Button, Heading, Label, Text} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'
import {clsx} from 'clsx'

import Styles from './PlanCard.module.css'

interface CtaAnalytics {
  marketingAnalyticsEvent: Parameters<typeof getAnalyticsEvent>[0]
  snakeCaseOptions?: Parameters<typeof getAnalyticsEvent>[1]
}

export type PlanCardProps = {
  label: string
  title: string
  description: string
  price: {
    value: number
    currency: string
    currencySymbol: string
    detailText: string
  }
  cta1: {
    label: string
    href: string
    analytics?: CtaAnalytics
  }
  cta2: {
    label: string
    href: string
    analytics?: CtaAnalytics
  }
  detailText: string
}

const PlanCard = (props: PlanCardProps) => {
  const {label, title, description, price, cta1, cta2, detailText} = props

  return (
    <div className={Styles['PlanCard']}>
      <Label className={clsx(Styles['PlanCard__label'])}>{label}</Label>

      <div className={Styles['PlanCard__content']}>
        <div className={Styles['PlanCard__titleBlock']}>
          <Heading size="4" as="h2">
            {title}
          </Heading>

          <Text variant="muted">{description}</Text>
        </div>

        <div className={Styles['PlanCard__price']}>
          <div className={Styles['PlanCard__priceTag']}>
            <Text font="hubot-sans" size="700" weight="normal">
              {price.currencySymbol}
              {price.value}
            </Text>

            <Text variant="muted">{price.currency}</Text>
          </div>

          <Text variant="muted">{price.detailText}</Text>
        </div>

        <div className={Styles['PlanCard__ctaBlock']}>
          <div>
            <Button
              href={cta1.href}
              as="a"
              variant="primary"
              hasArrow={false}
              block
              {...(cta1.analytics
                ? getAnalyticsEvent(cta1.analytics.marketingAnalyticsEvent, cta1.analytics.snakeCaseOptions)
                : {})}
            >
              {cta1.label}
            </Button>

            <Button
              href={cta2.href}
              as="a"
              hasArrow={false}
              block
              {...(cta2.analytics
                ? getAnalyticsEvent(cta2.analytics.marketingAnalyticsEvent, cta2.analytics.snakeCaseOptions)
                : {})}
            >
              {cta2.label}
            </Button>
          </div>

          <Text size="100" variant="muted">
            {detailText}
          </Text>
        </div>
      </div>
    </div>
  )
}

export default PlanCard
