import {Grid, Stack} from '@primer/react-brand'
import PricingCard from './PricingCard'
import {analyticsEvent} from '../../../../lib/analytics'
import VSCodeCta from './VSCodeCta'

interface PricingCardsNewProps {
  copilotProSignupPath: string
  copilotForBusinessSignupPath: string
  copilotEnterpriseSignupPath: string
  copilotBusinessContactSalesPath: string
  copilotEnterpriseContactSalesPath: string
  userHasOrgs: boolean
  headingLevel?: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6' | undefined
}

export default function PricingCardsNew({
  copilotProSignupPath,
  copilotForBusinessSignupPath,
  copilotEnterpriseSignupPath,
  copilotBusinessContactSalesPath,
  copilotEnterpriseContactSalesPath,
  userHasOrgs,
  headingLevel,
}: PricingCardsNewProps) {
  const copilotBusinessContactSalesUrl = `${copilotBusinessContactSalesPath}&utm_content=CopilotBusiness`
  const copilotEnterpriseContactSalesUrl = `${copilotEnterpriseContactSalesPath}&utm_content=CopilotEnterprise`

  interface AnalyticsEvent {
    action: string
    tag: string
    context: string
    location: string
  }

  interface CTA {
    text: string
    href: string
    variant: 'primary' | 'secondary'
    analyticsEvent: AnalyticsEvent
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

  const cardData: PricingCardContent[] = [
    {
      label: 'New',
      heading: 'Free',
      description: 'For developers looking to get started with GitHub Copilot.',
      price: '0',
      additionalCtas: <VSCodeCta smaller location="offer_cards" />,
      disclaimer: 'Includes up to 2,000 completions and 50 chat requests per month.',
      ctas: [
        {
          text: 'Get started',
          href: 'https://github.com/copilot',
          variant: 'primary',
          analyticsEvent: {
            action: 'get_started',
            tag: 'button',
            context: 'free_plan',
            location: 'offer_cards',
          },
          ariaLabel: 'Get started with GitHub Copilot Free',
        },
      ],
    },
    {
      label: !userHasOrgs ? 'Most popular' : undefined,
      heading: 'Pro',
      description: 'For developers who want unlimited access to GitHub Copilot.',
      price: '10',
      priceDescription: 'per month. First 30 days free.',
      disclaimer: (
        <>
          Free for verified students, teachers, and maintainers of popular open source projects.{' '}
          <a
            href="https://github.com/education"
            className="lp-Link--inline lp-Link--muted"
            {...analyticsEvent({
              action: 'learn_more',
              tag: 'link',
              context: 'education_pro_plan',
              location: 'offer_cards',
            })}
            aria-label="Learn more about GitHub Education"
          >
            Learn more
          </a>
        </>
      ),
      ctas: [
        {
          text: 'Get started',
          href: copilotProSignupPath,
          variant: 'primary',
          analyticsEvent: {
            action: 'get_started',
            tag: 'button',
            context: 'pro_plan',
            location: 'offer_cards',
          },
          ariaLabel: 'Get started with GitHub Copilot Pro',
        },
      ],
    },
    {
      label: userHasOrgs ? 'Popular for teams' : undefined,
      heading: 'Business',
      description: 'For teams ready to accelerate their workflows with GitHub Copilot.',
      price: '19',
      priceDescription: 'per user / month',
      ctas: [
        {
          text: 'Get started',
          href: copilotForBusinessSignupPath,
          variant: 'primary',
          analyticsEvent: {
            action: 'get_started',
            tag: 'button',
            context: 'business_plan',
            location: 'offer_cards',
          },
          ariaLabel: 'Get started with GitHub Copilot Business',
        },
        {
          text: 'Contact sales',
          href: copilotBusinessContactSalesUrl,
          variant: 'secondary',
          analyticsEvent: {
            action: 'contact_sales',
            tag: 'button',
            context: 'business_plan',
            location: 'offer_cards',
          },
          ariaLabel: 'Contact sales for GitHub Copilot Business',
        },
      ],
    },
    {
      heading: 'Enterprise',
      description: 'For organizations seeking a fully customized GitHub Copilot experience.',
      price: '39',
      priceDescription: 'per user / month',
      ctas: [
        {
          text: 'Get started',
          href: copilotEnterpriseSignupPath,
          variant: 'primary',
          analyticsEvent: {
            action: 'get_started',
            tag: 'button',
            context: 'enterprise_plan',
            location: 'offer_cards',
          },
          ariaLabel: 'Get started with GitHub Copilot Enterprise',
        },
        {
          text: 'Contact sales',
          href: copilotEnterpriseContactSalesUrl,
          variant: 'secondary',
          analyticsEvent: {
            action: 'contact_sales',
            tag: 'button',
            context: 'enterprise_plan',
            location: 'offer_cards',
          },
          ariaLabel: 'Contact sales for GitHub Copilot Enterprise',
        },
      ],
    },
  ]

  return (
    <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap text-center position-relative mt-0">
      <Grid.Column span={12} className="position-relative">
        <Grid className="lp-Pricing">
          <Grid.Column span={12} className="px-0 py-0">
            <Stack
              direction={{narrow: 'vertical', regular: 'horizontal'}}
              gap={{narrow: 48, regular: 16}}
              padding="none"
              className="lp-Pricing-cards"
            >
              {cardData.map(content => (
                <PricingCard key={content.heading} content={content} headingLevel={headingLevel} />
              ))}
            </Stack>
          </Grid.Column>
        </Grid>
      </Grid.Column>
    </Grid>
  )
}
