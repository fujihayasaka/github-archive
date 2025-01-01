import {Box, Button, Heading, Label, Stack, Text} from '@primer/react-brand'
import {analyticsEvent} from '../../../../lib/analytics'

interface CTA {
  text: string
  href: string
  variant: 'primary' | 'secondary'
  analyticsEvent: {
    action: string
    tag: string
    context: string
    location: string
  }
  ariaLabel: string
}

interface PricingCardContent {
  label?: string
  heading: string
  description: string
  price: string
  priceDescription?: string | JSX.Element
  disclaimer?: string | JSX.Element
  additionalCtas?: JSX.Element
  ctas: CTA[]
}

interface PricingCardProps {
  content: PricingCardContent
  headingLevel?: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6' | undefined
}

export default function PricingCard({content, headingLevel = 'h3'}: PricingCardProps) {
  return (
    <Stack padding="none" gap={20} style={{flex: '1'}} className="lp-Pricing-card has-BlurredBg has-GradientBorder">
      {content.label && (
        <div className="position-absolute top-n3 left-0 right-0">
          <div className="lp-ConicGradientBorder lp-ConicGradientBorder-label d-inline-block">
            <Label size="medium" color="purple-red" className="lp-ConicGradientBorder-label-inner">
              {content.label}
            </Label>
          </div>
        </div>
      )}

      <Box>
        <Heading as={headingLevel} size="5" className="lp-Pricing-card-heading">
          {content.heading}
        </Heading>

        <Text as="p" size="100" weight="normal" variant="muted" className="lp-Pricing-description--org">
          {content.description}
        </Text>
      </Box>

      <Box>
        <Stack
          direction="horizontal"
          gap={4}
          padding="none"
          className="lp-Pricing-price flex-justify-center flex-items-center"
        >
          <Text size="500" weight="normal" style={{lineHeight: 1}} className="lp-Pricing-currency is-sansSerifAlt">
            $
          </Text>

          <Text size="500" weight="normal" style={{lineHeight: 1}} className="lp-Pricing-number is-sansSerifAlt">
            {content.price}
          </Text>

          <Text
            size="100"
            weight="normal"
            variant="muted"
            className="is-sansSerifAlt"
            style={{alignSelf: 'start', lineHeight: '1.3'}}
          >
            {` USD `}
          </Text>
        </Stack>

        <Text size="100" weight="normal" variant="muted" className="lp-Pricing-price-description f6-mktg">
          {content.priceDescription ? content.priceDescription : <>&nbsp;</>}
        </Text>
      </Box>

      <Stack
        direction={{narrow: 'vertical', wide: 'vertical'}}
        gap={12}
        padding="none"
        className="lp-Pricing-pricing-ctas"
      >
        {content.ctas.map(cta => (
          <Button
            key={cta.text}
            as="a"
            href={cta.href}
            block
            variant={cta.variant}
            {...analyticsEvent(cta.analyticsEvent)}
            aria-label={cta.ariaLabel}
          >
            {cta.text}
          </Button>
        ))}

        {content.additionalCtas && content.additionalCtas}

        {content.disclaimer && (
          <Text variant="muted" className="d-block lp-Pricing-disclaimer f6-mktg mt-3 mt-md-0">
            {content.disclaimer}
          </Text>
        )}
      </Stack>
    </Stack>
  )
}
