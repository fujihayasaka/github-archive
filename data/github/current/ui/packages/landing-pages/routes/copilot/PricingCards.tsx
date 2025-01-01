import {Box, Button, Grid, Heading, Image, Label, SectionIntro, Stack, Text} from '@primer/react-brand'
import {analyticsEvent} from '../../lib/analytics'

interface PricingCardsProps {
  siteCopilotPurchaseRefresh: boolean
  copilotSignupPath: string
  copilotForBusinessSignupPath: string
  copilotForBusinessSignupPathRefresh: string
  copilotEnterpriseSignupPath: string
  copilotContactSalesPath: string
  pricingExperience: string
}

export function PricingCards({
  siteCopilotPurchaseRefresh,
  copilotSignupPath,
  copilotForBusinessSignupPath,
  copilotForBusinessSignupPathRefresh,
  copilotEnterpriseSignupPath,
  copilotContactSalesPath,
  pricingExperience,
}: PricingCardsProps) {
  const copilotBusinessContactSalesPath = `${copilotContactSalesPath}&utm_content=CopilotBusiness`
  const copilotEnterpriseContactSalesPath = `${copilotContactSalesPath}&utm_content=CopilotEnterprise`

  return (
    <div>
      <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap text-center position-relative">
        <Grid.Column span={12}>
          <SectionIntro align="center" fullWidth className="lp-SectionIntro">
            <SectionIntro.Label size="large" className="lp-Label--section">
              Pricing
            </SectionIntro.Label>
            <SectionIntro.Heading size="2" weight="semibold">
              Take flight with GitHub&nbsp;Copilot
            </SectionIntro.Heading>
            <SectionIntro.Description className="lp-SectionIntro-description">
              Organizations and developers all over the world use GitHub Copilot to code faster, drive impact, and focus
              on doing what matters most: building great software.
            </SectionIntro.Description>
          </SectionIntro>
        </Grid.Column>

        <Grid.Column span={12} className="position-relative">
          <Grid className="lp-Pricing">
            <Grid.Column span={12} className="px-0 py-0">
              <Stack
                direction={{narrow: 'vertical', regular: 'horizontal'}}
                gap={{narrow: 48, regular: 32}}
                padding="none"
              >
                {/* Copilot Individual */}
                <Stack
                  padding="none"
                  gap={24}
                  style={{flex: '1'}}
                  className="pt-4 pb-6 pb-md-4 px-5 px-md-6 lp-Pricing-item lp-Pricing-item-card has-BlurredBg has-GradientBorder"
                >
                  <Box>
                    <Box marginBlockStart={16} marginBlockEnd={16}>
                      <Heading as="h3" size="5" className="lp-pricing-card-heading">
                        Copilot
                        <br />
                        Individual
                      </Heading>
                    </Box>
                    <Text as="p" size="200" weight="normal" variant="muted" className="lp-Pricing-description--org">
                      For individual developers, freelancers, students, and educators that want to code faster and
                      happier.
                    </Text>
                  </Box>

                  <Box>
                    <Stack
                      direction="horizontal"
                      gap={12}
                      padding="none"
                      className="lp-Pricing-price flex-justify-center pt-5"
                    >
                      <Text size="500" weight="normal" style={{lineHeight: 1.4}} className="is-sansSerifAlt">
                        $
                      </Text>
                      <Text weight="normal" className="lp-Pricing-nr is-sansSerifAlt">
                        10
                      </Text>
                      <Text size="500" weight="normal" className="is-sansSerifAlt" style={{alignSelf: 'end'}}>
                        USD
                      </Text>
                    </Stack>

                    <Text size="100" weight="normal" variant="muted" className="d-block mt-2">
                      per month / $100 USD per year
                    </Text>
                  </Box>

                  <Stack
                    direction={{narrow: 'vertical', wide: 'vertical'}}
                    gap={12}
                    padding="none"
                    className="lp-Pricing-pricing-ctas"
                  >
                    <Button
                      as="a"
                      href={copilotSignupPath}
                      block
                      variant="primary"
                      {...analyticsEvent({
                        action: 'start_trial',
                        tag: 'button',
                        context: 'individual_plan',
                        location: 'offer_cards',
                      })}
                    >
                      Start a free trial
                    </Button>

                    <Text variant="muted" className="d-block lp-Pricing-disclaimer f6-mktg mt-3 mt-md-0">
                      Free for verified students, teachers, and maintainers of popular open source projects.
                    </Text>
                  </Stack>
                </Stack>

                {/* Copilot Business */}
                <Stack
                  padding="none"
                  gap={24}
                  style={{flex: '1'}}
                  className="pt-4 pb-6 pb-md-4 px-5 px-md-6 position-relative lp-Pricing-item lp-Pricing-item-card has-BlurredBg has-GradientBorder"
                >
                  <Box>
                    <div className="position-absolute top-n3 left-0 right-0">
                      <div className="lp-ConicGradientBorder lp-ConicGradientBorder-label d-inline-block">
                        <Label size="medium" color="purple-red" className="lp-ConicGradientBorder-label-inner">
                          Most popular
                        </Label>
                      </div>
                    </div>
                    <Box marginBlockStart={16} marginBlockEnd={16}>
                      <Heading as="h3" size="5" className="lp-pricing-card-heading">
                        Copilot
                        <br />
                        Business
                      </Heading>
                    </Box>
                    <Text as="p" size="200" weight="normal" variant="muted" className="lp-Pricing-description--org">
                      For organizations ready to improve engineering velocity, code quality, and developer experience.
                    </Text>
                  </Box>

                  <Box>
                    <Stack
                      direction="horizontal"
                      gap={12}
                      padding="none"
                      className="lp-Pricing-price flex-justify-center pt-5"
                    >
                      <Text size="500" weight="normal" style={{lineHeight: 1.4}} className="is-sansSerifAlt">
                        $
                      </Text>
                      <Text weight="normal" className="lp-Pricing-nr is-sansSerifAlt">
                        19
                      </Text>
                      <Text size="500" weight="normal" className="is-sansSerifAlt" style={{alignSelf: 'end'}}>
                        USD
                      </Text>
                    </Stack>

                    <Text size="100" weight="normal" variant="muted" className="d-block mt-2">
                      per user / month
                    </Text>
                  </Box>

                  <Stack
                    direction={{narrow: 'vertical', wide: 'vertical'}}
                    gap={12}
                    padding="none"
                    className="lp-Pricing-pricing-ctas"
                  >
                    {siteCopilotPurchaseRefresh ? (
                      <Button
                        as="a"
                        href={copilotForBusinessSignupPathRefresh}
                        block
                        variant="primary"
                        {...analyticsEvent({
                          action: 'buy_now',
                          tag: 'button',
                          context: 'business_plan',
                          location: 'offer_cards',
                        })}
                      >
                        Buy now
                      </Button>
                    ) : (
                      <Button
                        as="a"
                        href={copilotForBusinessSignupPath}
                        block
                        variant="primary"
                        {...analyticsEvent({
                          action: 'buy_now',
                          tag: 'button',
                          context: 'business_plan',
                          location: 'offer_cards',
                        })}
                      >
                        Buy now
                      </Button>
                    )}

                    <Button
                      as="a"
                      href={copilotBusinessContactSalesPath}
                      block
                      variant="secondary"
                      {...analyticsEvent({
                        action: 'contact_sales',
                        tag: 'button',
                        context: 'business_plan',
                        location: 'offer_cards',
                      })}
                    >
                      Contact sales
                    </Button>
                  </Stack>
                </Stack>

                {/* Copilot Enterprise */}
                <Stack
                  padding="none"
                  gap={24}
                  style={{flex: '1'}}
                  className="pt-4 pb-6 pb-md-4 px-5 px-md-6 position-relative lp-Pricing-item lp-Pricing-item-card has-BlurredBg has-GradientBorder"
                >
                  <Box>
                    <div className="position-absolute top-n3 left-0 right-0">
                      <div className="lp-ConicGradientBorder lp-ConicGradientBorder-label d-inline-block">
                        <Label size="medium" color="purple-red" className="lp-ConicGradientBorder-label-inner">
                          New
                        </Label>
                      </div>
                    </div>
                    <Box marginBlockStart={16} marginBlockEnd={16}>
                      <Heading as="h3" size="5" className="lp-pricing-card-heading">
                        Copilot
                        <br />
                        Enterprise
                      </Heading>
                    </Box>
                    <Text as="p" size="200" weight="normal" variant="muted" className="lp-Pricing-description--org">
                      For companies looking for the most customization based on their organization’s knowledge and
                      codebase.
                    </Text>
                  </Box>

                  <Box>
                    <Stack
                      direction="horizontal"
                      gap={12}
                      padding="none"
                      className="lp-Pricing-price flex-justify-center pt-5"
                    >
                      <Text size="500" weight="normal" style={{lineHeight: 1.4}} className="is-sansSerifAlt">
                        $
                      </Text>
                      <Text weight="normal" className="lp-Pricing-nr is-sansSerifAlt">
                        39
                      </Text>
                      <Text size="500" weight="normal" className="is-sansSerifAlt" style={{alignSelf: 'end'}}>
                        USD
                      </Text>
                    </Stack>

                    <Text size="100" weight="normal" variant="muted" className="d-block mt-2">
                      per user / month
                    </Text>
                  </Box>

                  {siteCopilotPurchaseRefresh ? (
                    <Stack
                      direction={{narrow: 'vertical', wide: 'vertical'}}
                      gap={12}
                      padding="none"
                      className="lp-Pricing-pricing-ctas"
                    >
                      <Button
                        as="a"
                        href={copilotEnterpriseSignupPath}
                        block
                        variant="primary"
                        {...analyticsEvent({
                          action: 'buy_now',
                          tag: 'button',
                          context: 'enterprise_plan',
                          location: 'offer_cards',
                        })}
                      >
                        Buy now
                      </Button>
                      <Button
                        as="a"
                        href={copilotEnterpriseContactSalesPath}
                        variant="secondary"
                        {...analyticsEvent({
                          action: 'contact_sales',
                          tag: 'button',
                          context: 'enterprise_plan',
                          location: 'offer_cards',
                        })}
                      >
                        Contact sales
                      </Button>
                    </Stack>
                  ) : (
                    <Stack
                      direction={{narrow: 'vertical', wide: 'vertical'}}
                      gap={12}
                      padding="none"
                      className="lp-Pricing-pricing-ctas"
                    >
                      <Button
                        as="a"
                        href={copilotEnterpriseContactSalesPath}
                        variant="primary"
                        {...analyticsEvent({
                          action: 'contact_sales',
                          tag: 'button',
                          context: 'enterprise_plan',
                          location: 'offer_cards',
                        })}
                      >
                        Contact sales
                      </Button>
                    </Stack>
                  )}
                </Stack>
              </Stack>
            </Grid.Column>
          </Grid>
        </Grid.Column>
      </Grid>

      {pricingExperience === 'existing_experience' && (
        <div className="lp-Pricing-bgCover">
          <Image
            className="lp-Pricing-bgCoverImage"
            src="/images/modules/site/copilot/pricing-cover.svg"
            loading="lazy"
            alt=""
          />
        </div>
      )}
    </div>
  )
}
