import {Bento, Hero, Image, Link} from '@primer/react-brand'
import {getAnalyticsEvent} from '@github-ui/swp-core/lib/utils/analytics'

import Logos from '../../components/Logos/Logos'
import Spacer from '../../components/Spacer/Spacer'

import COPY from './Hero.data'
import imgBackground from './hero-bg.webp'

export default function HeroSection() {
  return (
    <section id="hero" className="lp-Hero">
      <div className="lp-Hero-bg">
        <Image src={imgBackground} alt="" width={1600} />
      </div>

      <div className="lp-Container">
        <Hero data-hpc align="center" className="lp-Hero-content">
          <Hero.Label color="green-blue" className="lp-Hero-label">
            {COPY.label}
          </Hero.Label>

          <Hero.Heading size="1" className="lp-Hero-heading">
            {COPY.title[0]} <br className="lp-break-whenWide" /> {COPY.title[1]}
          </Hero.Heading>

          <Hero.PrimaryAction
            href={COPY.cta1.href}
            hasArrow={false}
            className="lp-Hero-ctaButton"
            {...getAnalyticsEvent(COPY.cta1.analytics.marketingAnalyticsEvent)}
          >
            {COPY.cta1.label}
          </Hero.PrimaryAction>

          <Hero.SecondaryAction
            href={COPY.cta2.href}
            hasArrow={false}
            className="lp-Hero-ctaButton"
            {...getAnalyticsEvent(COPY.cta2.analytics.marketingAnalyticsEvent)}
          >
            {COPY.cta2.label}
          </Hero.SecondaryAction>
        </Hero>

        <Spacer size="44px" size768="68px" />

        <Bento>
          {COPY.bentos.map((bento, index) => (
            <Bento.Item
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={`bento_${index}`}
              columnSpan={{xsmall: 12, medium: 6}}
              visualAsBackground
              className="lp-Hero-bentoItem"
            >
              <Bento.Content>
                <Bento.Heading as="h2" size="5" weight="semibold">
                  {bento.title[0]} <br /> {bento.title[1]}
                </Bento.Heading>
                <Link
                  variant="default"
                  href={bento.link.href}
                  {...getAnalyticsEvent(bento.link.analytics.marketingAnalyticsEvent)}
                >
                  {bento.link.label}
                </Link>
              </Bento.Content>

              <Bento.Visual>
                <Image
                  as="picture"
                  alt=""
                  width="600"
                  src={bento.img.sm}
                  sources={[
                    {
                      srcset: bento.img.lg,
                      media: '(min-width: 544px)',
                    },
                  ]}
                />
              </Bento.Visual>
            </Bento.Item>
          ))}
        </Bento>

        <Spacer size="32px" size768="56px" />

        <Logos data={COPY.logos} />
      </div>
    </section>
  )
}
