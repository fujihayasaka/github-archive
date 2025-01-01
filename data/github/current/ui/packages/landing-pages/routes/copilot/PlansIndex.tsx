import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Footnotes, Grid, SubNav, Text, ThemeProvider} from '@primer/react-brand'
import {Spacer} from '../features/components/Spacer'

import {Image} from './../../components/Image/Image'

import {CallToAction} from './CallToAction'
import {PricingTable} from './PricingTable'
import {PricingCards} from './PricingCards'
import {BannerTryAllOfGitHub} from './BannerTryAllOfGitHub'
import {analyticsEvent, cohortFunnelBuilder} from '../../lib/analytics'
import {SUBNAV_LINKS} from './SubNav.data'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

export function CopilotPlansIndex() {
  const {siteCopilotPurchaseRefresh} = useRoutePayload<{siteCopilotPurchaseRefresh: boolean}>()
  let {copilotSignupPath} = useRoutePayload<{copilotSignupPath: string}>()
  let {copilotForBusinessSignupPath} = useRoutePayload<{copilotForBusinessSignupPath: string}>()
  let {copilotForBusinessSignupPathRefresh} = useRoutePayload<{copilotForBusinessSignupPathRefresh: string}>()
  let {copilotEnterpriseSignupPath} = useRoutePayload<{copilotEnterpriseSignupPath: string}>()
  let {copilotContactSalesPath} = useRoutePayload<{copilotContactSalesPath: string}>()
  const {cft} = useRoutePayload<{cft: string}>()
  const isDigitalFrontDoorEnabled = useFeatureFlag('digital_front_door_mvp')

  const withCft = cohortFunnelBuilder(cft)

  copilotSignupPath = withCft(copilotSignupPath, {product: 'cfi'})
  copilotForBusinessSignupPath = withCft(copilotForBusinessSignupPath, {product: 'cfb'})
  copilotForBusinessSignupPathRefresh = withCft(copilotForBusinessSignupPathRefresh, {product: 'cfb'})
  copilotEnterpriseSignupPath = withCft(copilotEnterpriseSignupPath, {product: 'ce'})
  copilotContactSalesPath = withCft(copilotContactSalesPath)

  return (
    <ThemeProvider colorMode="dark" className="lp-Copilot">
      {/* Header 72px */}
      <Spacer size="66px" size768="72px" />
      <SubNav className="lp-Hero-subnav">
        <SubNav.Heading
          href={SUBNAV_LINKS.logo.url}
          className="d-block mr-3 mr-lg-4 position-relative lp-Hero-subnav-heading"
        >
          {SUBNAV_LINKS.logo.label}
          <Text className="lp-Hero-subnav-separator" size="300" weight="semibold" aria-hidden="true">
            /
          </Text>
        </SubNav.Heading>
        {SUBNAV_LINKS.items.map((item, index) => (
          <SubNav.Link
            // eslint-disable-next-line @eslint-react/no-array-index-key
            key={`subnav_${index}`}
            href={!index ? item.url : '#'}
            className={!index ? 'selected' : ''}
            aria-current={index ? 'page' : undefined}
          >
            {item.label}
          </SubNav.Link>
        ))}
      </SubNav>

      <Spacer size="52px" size768="0px" />

      <section id="pricing" className="lp-Section lp-Section--pricing">
        <Image
          as="picture"
          src="/images/modules/site/copilot/pricing-gradient.jpg"
          className="position-absolute top-0 left-0 width-100 height-100"
          sources={[
            {
              srcset: '/images/modules/site/copilot/pricing-gradient-sm.jpg',
              media: '(max-width: 767px)',
            },
            {
              srcset: '/images/modules/site/copilot/pricing-gradient.jpg',
              media: '(min-width: 768px) and (max-width: 1279px)',
            },
            {
              srcset: '/images/modules/site/copilot/pricing-gradient-lg.jpg',
              media: '(min-width: 1280px)',
            },
          ]}
          alt=""
        />
        <PricingCards
          siteCopilotPurchaseRefresh={siteCopilotPurchaseRefresh}
          copilotSignupPath={withCft(copilotSignupPath, {product: 'cfi'})}
          copilotForBusinessSignupPath={withCft(copilotForBusinessSignupPath, {product: 'cfb'})}
          copilotForBusinessSignupPathRefresh={withCft(copilotForBusinessSignupPathRefresh, {product: 'cfb'})}
          copilotEnterpriseSignupPath={withCft(copilotEnterpriseSignupPath, {product: 'ce'})}
          copilotContactSalesPath={withCft(copilotContactSalesPath)}
          pricingExperience="existing_experience"
        />
      </section>

      {isDigitalFrontDoorEnabled && (
        <section className="lp-Section pt-0 pb-0 px-6" data-testid="dfd_banner">
          <BannerTryAllOfGitHub copilotForBusinessSignupPath={copilotForBusinessSignupPath} />
        </section>
      )}

      <section className="lp-Section pt-0">
        <PricingTable
          copilotSignupPath={copilotSignupPath}
          copilotForBusinessSignupPath={copilotForBusinessSignupPath}
          copilotContactSalesPath={copilotContactSalesPath}
          footnotesModifier={-1}
        />

        <div className="mt-8">
          <CallToAction copilotContactSalesPath={copilotContactSalesPath} />
        </div>
      </section>

      <section id="footnotes" className="lp-Section lp-Section--footnotes" style={{paddingTop: '0'}}>
        <Grid className="lp-Grid--noRowGap">
          <Grid.Column span={12}>
            <Footnotes>
              <Footnotes.Item id="footnote-1" href="#footnote-ref-1-1">
                Feature in public beta for Copilot Individual and Business plans. Requires use of repositories, issues,
                discussions, Actions, and other features of GitHub.
              </Footnotes.Item>

              <Footnotes.Item id="footnote-2" href="#footnote-ref-2-1">
                <a
                  className="lp-Link--inline"
                  href="https://docs.github.com/en/enterprise-cloud@latest/authentication/authenticating-with-saml-single-sign-on/about-authentication-with-saml-single-sign-on"
                  {...analyticsEvent({
                    action: 'saml_sso',
                    tag: 'link',
                    context: 'footnote',
                    location: 'features_table',
                  })}
                >
                  Authentication with SAML single sign-on (SSO)
                </a>{' '}
                available for organizations using GitHub Enterprise Cloud.
              </Footnotes.Item>
            </Footnotes>
          </Grid.Column>
        </Grid>
      </section>
    </ThemeProvider>
  )
}
