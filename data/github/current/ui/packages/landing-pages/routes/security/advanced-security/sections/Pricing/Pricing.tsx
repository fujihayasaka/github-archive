import {Image, SectionIntro} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import PlanCard from '../../../../../brand/components/PlanCard/PlanCard'

import Spacer from '../../components/Spacer/Spacer'

import imgIcon from './pricing-icon.webp'
import imgBgDesktop from './pricing-bg-desktop.webp'
import imgBgMobile from './pricing-bg-mobile.webp'

import COPY from './Pricing.data'
import Styles from './Pricing.module.css'

export default function PricingSection() {
  return (
    <section
      id="pricing"
      className={Styles.Pricing}
      style={{
        ['--bg-desktop']: `url("${imgBgDesktop}")`,
        ['--bg-mobile']: `url("${imgBgMobile}")`,
      }}
    >
      <div className="lp-Container">
        <Spacer size="64px" size768="182px" />

        <div className={Styles.PricingIcon}>
          <Image src={imgIcon} alt="" width={112} loading="lazy" />
        </div>

        <Spacer size="32px" size768="48px" />

        <SectionIntro align="center" fullWidth style={{padding: '0'}}>
          <SectionIntro.Heading as="h2" size="3">
            {COPY.title}
          </SectionIntro.Heading>

          <SectionIntro.Description className={Styles.SectionIntroDescription}>
            {COPY.description}
          </SectionIntro.Description>

          <SectionIntro.Link
            href={COPY.link.href}
            className={Styles.SectionIntroLink}
            {...getAnalyticsEvent(COPY.link.analytics.marketingAnalyticsEvent)}
          >
            {COPY.link.label}
          </SectionIntro.Link>
        </SectionIntro>

        <Spacer size="64px" size768="88px" />

        <div className={Styles.PricingPlans}>
          {COPY.plans.map((plan, index) => (
            // eslint-disable-next-line @eslint-react/no-array-index-key
            <PlanCard key={`plan_${index}`} {...plan} />
          ))}
        </div>

        <Spacer size="96px" size768="322px" />
      </div>
    </section>
  )
}
