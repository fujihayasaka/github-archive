import {Grid, SectionIntro, Text} from '@primer/react-brand'
import PricingCards from './PricingCards'
import PricingTable from './PricingTable'
import IdeList from './IdeList'

interface PricingSectionProps {
  copilotProSignupPath: string
  copilotForBusinessSignupPath: string
  copilotEnterpriseSignupPath: string
  copilotBusinessContactSalesPath: string
  copilotEnterpriseContactSalesPath: string
  userHasOrgs?: boolean
  isExpanded?: boolean
  showLabel?: boolean
  className?: string
  headingLevel?: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6' | undefined
}

export default function PricingSection({
  copilotProSignupPath,
  copilotForBusinessSignupPath,
  copilotEnterpriseSignupPath,
  copilotBusinessContactSalesPath,
  copilotEnterpriseContactSalesPath,
  userHasOrgs = true,
  isExpanded = false,
  showLabel = true,
  className = '',
  headingLevel = 'h2',
}: PricingSectionProps) {
  return (
    <section
      id="pricing"
      className={`lp-Section lp-Section--compact lp-SectionIntro--regular lp-Section--pricing mb-0 ${className}`}
    >
      <Grid className="lp-Section-con}tainer--centerUntilMedium lp-Grid--noRowGap text-center position-relative">
        <Grid.Column span={12}>
          <SectionIntro align="center" fullWidth className="lp-SectionIntro">
            {showLabel && (
              <SectionIntro.Label size="large" className="lp-Label--section">
                Pricing
              </SectionIntro.Label>
            )}

            <SectionIntro.Heading as={headingLevel} size="2" weight="semibold">
              Take flight with GitHub&nbsp;Copilot
            </SectionIntro.Heading>
          </SectionIntro>
        </Grid.Column>
      </Grid>

      <PricingCards
        copilotProSignupPath={copilotProSignupPath}
        copilotForBusinessSignupPath={copilotForBusinessSignupPath}
        copilotEnterpriseSignupPath={copilotEnterpriseSignupPath}
        copilotBusinessContactSalesPath={copilotBusinessContactSalesPath}
        copilotEnterpriseContactSalesPath={copilotEnterpriseContactSalesPath}
        userHasOrgs={userHasOrgs}
        headingLevel={headingLevel === 'h1' ? 'h2' : 'h3'}
      />

      <div className="lp-Pricing-IDE-section">
        <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap text-center position-relative">
          <Grid.Column span={12}>
            <Text as="div" size="200" variant="muted" weight="medium" style={{marginBottom: 'var(--base-size-24)'}}>
              GitHub Copilot is available on your favorite platforms:
            </Text>
            <IdeList type="small" location="pricing-cards" />
          </Grid.Column>
        </Grid>
      </div>

      {isExpanded && (
        <PricingTable
          copilotProSignupPath={copilotProSignupPath}
          copilotForBusinessSignupPath={copilotForBusinessSignupPath}
          copilotEnterpriseSignupPath={copilotEnterpriseSignupPath}
        />
      )}

      {!isExpanded && (
        <div className="lp-Section--new-pricing-experience-table">
          <details>
            <summary className="p-0">
              <h3>Compare all features</h3>
              <div style={{position: 'relative'}} className="pl-5" aria-hidden="true">
                <span className="icon-collapsed pl-3" />
                <span className="icon-expanded pl-2" />
              </div>
            </summary>
            <PricingTable
              copilotProSignupPath={copilotProSignupPath}
              copilotForBusinessSignupPath={copilotForBusinessSignupPath}
              copilotEnterpriseSignupPath={copilotEnterpriseSignupPath}
            />
          </details>
        </div>
      )}
    </section>
  )
}
