import {Button, Heading, Label, Text} from '@primer/react-brand'
import {clsx} from 'clsx'

import Styles from './PlanCard.module.css'

export interface PlanCardProps {
  label: string
  labelColor?: 'default' | 'green'
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
  }
  cta2: {
    label: string
    href: string
  }
  detailText: string
}

const defaultProps: Partial<PlanCardProps> = {
  labelColor: 'default',
}

const PlanCard: React.FC<PlanCardProps> = props => {
  const initializedProps = {...defaultProps, ...props}
  const {label, labelColor, title, description, price, cta1, cta2, detailText} = initializedProps

  return (
    <div className={Styles['PlanCard']}>
      <Label
        className={clsx(
          Styles['PlanCard__label'],
          // @ts-expect-error: The generated class name is valid
          Styles[`PlanCard__label--${labelColor}`],
        )}
      >
        {label}
      </Label>

      <div className={Styles['PlanCard__content']}>
        <div className={Styles['PlanCard__titleBlock']}>
          <Heading size="5" as="h2" className={Styles['PlanCard__title']}>
            {title}
          </Heading>
          <Text className={Styles['PlanCard__description']} variant="muted">
            {description}
          </Text>
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
            <Button href={cta1.href} as="a" variant="primary" block>
              {cta1.label}
            </Button>
            <Button href={cta2.href} as="a" block>
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
