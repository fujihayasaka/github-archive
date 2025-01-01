import {clsx} from 'clsx'

import {Bento, Image, SectionIntro, Testimonial, Text} from '@primer/react-brand'
import {CopilotIcon, ShieldLockIcon} from '@primer/octicons-react'

import Spacer from '../../components/Spacer/Spacer'

import imgBento1 from './bento-1.webp'
import imgBento2 from './bento-2.webp'
import imgBento3 from './bento-3.webp'
import imgBento1Bg from './bento-1-bg.webp'
import imgBento2Bg from './bento-2-bg.webp'
import imgBento3Bg from './bento-3-bg.webp'

import COPY from './Features.data'
import Styles from './Features.module.css'

export default function FeaturesSection() {
  return (
    <section id="features" className={Styles.Section}>
      <div className="lp-Container">
        <Spacer size="32px" size768="64px" />

        <SectionIntro align="center" fullWidth>
          <SectionIntro.Heading as="h2" size="3">
            {COPY.title}
          </SectionIntro.Heading>

          <SectionIntro.Description className={Styles.SectionIntroDescription}>
            {COPY.description}
          </SectionIntro.Description>
        </SectionIntro>

        <Spacer size="24px" size768="64px" />

        <Bento>
          {/* Bento 1 */}
          <Bento.Item
            columnSpan={12}
            style={{
              backgroundSize: 'cover',
              backgroundImage: `url("${imgBento1Bg}"`,
            }}
          >
            <Bento.Visual horizontalAlign="center" fillMedia={false} className="lp-Features-bentoVisual1">
              <Image
                src={imgBento1}
                alt="Screenshot displaying a code snippet with an Express.js application setup and a CodeQL scan result indicating a high-severity reflected cross-site scripting vulnerability due to user-provided value. The GitHub Copilot Autofix feature is generating a fix suggestion."
                width="986"
                height="555"
                loading="lazy"
                className="lp-Features-bentoImg1"
              />
            </Bento.Visual>
          </Bento.Item>

          {/* Bento 2 */}
          <Bento.Item
            className="lp-Features-bento2"
            columnSpan={{xsmall: 12, medium: 6}}
            style={{
              backgroundSize: 'cover',
              backgroundImage: `url(${imgBento2Bg}`,
            }}
          >
            <Bento.Content leadingVisual={<CopilotIcon size={16} />} className="lp-BentoContent lp-Bento--withBadge">
              <Bento.Heading as="h3" size="5" weight="semibold" className="text-wrap-balance">
                {COPY.bento2.title}
              </Bento.Heading>

              <Text variant="default" size="300" className={clsx(Styles.BentoDescription, 'mt-3')}>
                {COPY.bento2.description}
              </Text>
            </Bento.Content>

            <Bento.Visual
              fillMedia={false}
              padding="normal"
              horizontalAlign="center"
              verticalAlign="center"
              className={Styles.BentoVisual}
            >
              <Image
                src={imgBento2}
                alt="Screenshot displaying a code snippet with a highlighted Copilot Autofix suggestion. The original code sends a response with user-provided query name directly, and the suggested fix escapes the user-provided query name to prevent cross-site scripting vulnerability."
                width="529"
                height="189"
                loading="lazy"
                className="lp-Features-bentoImg lp-borderRadiusNone"
              />
            </Bento.Visual>
          </Bento.Item>

          {/* Bento 3 */}
          <Bento.Item
            className="lp-Features-bento3"
            columnSpan={{xsmall: 12, medium: 6}}
            style={{
              backgroundSize: 'cover',
              backgroundImage: `url(${imgBento3Bg}`,
            }}
          >
            <Bento.Content leadingVisual={<ShieldLockIcon size={16} />} className="lp-BentoContent lp-Bento--withBadge">
              <Bento.Heading as="h3" size="5" weight="semibold" className="text-wrap-balance">
                {COPY.bento3.title}
              </Bento.Heading>

              <Text variant="default" size="300" className={clsx(Styles.BentoDescription, 'mt-3')}>
                {COPY.bento3.description}
              </Text>
            </Bento.Content>

            <Bento.Visual
              fillMedia={false}
              padding="normal"
              horizontalAlign="center"
              verticalAlign="center"
              className={Styles.BentoVisual}
            >
              <Image
                src={imgBento3}
                alt="Screenshot of a terminal output showing a git push command failure due to GitHub Push Protection detecting secrets. The error message 'error GH009: Secrets detected! This push failed.' is displayed, instructing the user to resolve the secrets before pushing again."
                width="529"
                height="190"
                loading="lazy"
                className="lp-Features-bentoImg lp-borderRadiusNone"
              />
            </Bento.Visual>
          </Bento.Item>
        </Bento>

        <Spacer size="20px" size768="32px" />

        <Testimonial
          variant="subtle"
          size="large"
          quoteMarkColor="green"
          className="lp-Features-testimonial px-4 px-md-16"
        >
          <Testimonial.Quote>{COPY.testimonial.quote}</Testimonial.Quote>
          <Testimonial.Name position={COPY.testimonial.position}>{COPY.testimonial.name}</Testimonial.Name>
        </Testimonial>
      </div>
    </section>
  )
}
