import {PulseIcon, ShieldCheckIcon, ShieldLockIcon, TriangleDownIcon, TriangleUpIcon} from '@primer/octicons-react'
import {Bento, Image, SectionIntro, Text} from '@primer/react-brand'

export default function EnterpriseSection() {
  return (
    <section id="enterprise">
      <div className="lp-Container">
        <div
          className="lp-Spacer"
          style={{'--lp-space': '64px', '--lp-space-xl': '128px'} as React.CSSProperties}
          aria-hidden
        />

        <SectionIntro align="center" fullWidth>
          <SectionIntro.Label className="lp-SectionIntroLabel--muted">Enterprise-ready</SectionIntro.Label>
          <SectionIntro.Heading as="h2" size="2" weight="semibold">
            Fixes in minutes, <br className="lp-break-whenNarrow" /> not months.
          </SectionIntro.Heading>
          <SectionIntro.Description className="lp-Enterprise-sectionIntroDescription">
            With AI-powered remediation, static analysis, secret scanning, and software composition analysis, GitHub
            Advanced Security helps developers and security teams work together to eliminate security debt and keep new
            vulnerabilities out of code.
          </SectionIntro.Description>
        </SectionIntro>

        <div className="lp-Spacer" style={{'--lp-space': '64px'} as React.CSSProperties} aria-hidden />

        <Bento>
          {/* Bento 1 */}
          <Bento.Item columnSpan={{xsmall: 12, medium: 7}} rowSpan={{xsmall: 4, medium: 5}} visualAsBackground>
            <Bento.Content
              horizontalAlign="center"
              verticalAlign="center"
              padding={{xsmall: 'normal', medium: 'spacious'}}
            >
              <Bento.Heading
                as="h3"
                size="4"
                weight="semibold"
                className="lp-letterSpacing700-whenWide lp-fontSize32-whenNarrow"
                style={{margin: '0'}}
              >
                Secure code, accelerated
              </Bento.Heading>
            </Bento.Content>
            <Bento.Visual>
              <Image
                src="/images/modules/site/enterprise/advanced-security/enterprise-bento-1.jpg"
                alt=""
                width="724"
                height="500"
                loading="lazy"
              />
            </Bento.Visual>
          </Bento.Item>

          {/* Bento 2 */}
          <Bento.Item
            columnSpan={{xsmall: 12, medium: 5}}
            rowSpan={{xsmall: 4, medium: 5}}
            visualAsBackground
            className="lp-Enterprise-bentoItem"
          >
            <Bento.Content
              horizontalAlign="center"
              verticalAlign="center"
              padding={{xsmall: 'normal', medium: 'spacious'}}
              leadingVisual={<PulseIcon />}
              className="lp-Bento--withAccentIcon lp-Bento--iconWithThickerStroke"
            >
              <Bento.Heading
                as="h3"
                className="lp-Enterprise-bentoStatsText lp-is-sansSerifAlt lp-letterSpacing700-whenWide"
                style={{marginBottom: '24px', lineHeight: '100%'}}
              >
                <span className="lp-Color-accent">28</span> <br /> minutes
              </Bento.Heading>
              <Text as="div" variant="muted" style={{marginBottom: '0'}}>
                From vulnerability detection to successful remediation
                <sup>1</sup>
              </Text>
            </Bento.Content>
          </Bento.Item>

          {/* Bento 3 */}
          <Bento.Item
            columnSpan={{xsmall: 12, medium: 5}}
            rowSpan={{xsmall: 4, medium: 5}}
            visualAsBackground
            className="lp-Enterprise-bentoItem"
          >
            <Bento.Content
              horizontalAlign="center"
              verticalAlign="center"
              padding={{xsmall: 'normal', medium: 'spacious'}}
              leadingVisual={<TriangleDownIcon />}
              className="lp-Bento--withAccentIcon lp-Bento--iconWithThickerStroke"
            >
              <Bento.Heading
                as="h3"
                className="lp-Enterprise-bentoStatsText lp-is-sansSerifAlt lp-letterSpacing700-whenWide"
                style={{marginBottom: '24px', lineHeight: '100%'}}
              >
                <span className="lp-Color-accent">2.4x</span> <br /> more <br /> precise
              </Bento.Heading>
              <Text as="div" variant="muted" style={{marginBottom: '0'}}>
                Finds leaked secrets with <br className="lp-breakWhenWide" /> fewer false positives.<sup>2</sup>
                <div className="lp-Bento--iconWithThickerStroke" style={{marginTop: '32px'}}>
                  <TriangleUpIcon size={44} className="lp-Color-accent" />
                </div>
              </Text>
            </Bento.Content>
          </Bento.Item>

          {/* Bento 4 */}
          <Bento.Item
            columnSpan={{xsmall: 12, medium: 7}}
            rowSpan={{xsmall: 4, medium: 5}}
            style={{
              backgroundSize: 'cover',
              backgroundImage: 'url("/images/modules/site/enterprise/advanced-security/enterprise-bento-4.jpg")',
              gridTemplateRows: '1fr 1fr',
              rowGap: '0',
            }}
          >
            <Bento.Content
              horizontalAlign="center"
              verticalAlign="end"
              leadingVisual={<ShieldLockIcon />}
              className="lp-Bento--iconWithThickerStroke"
            >
              <Bento.Heading
                as="h3"
                size="4"
                weight="semibold"
                className="lp-letterSpacing700-whenWide lp-fontSize28-whenNarrow"
              >
                Prevent secret leaks
              </Bento.Heading>
            </Bento.Content>
            <Bento.Visual
              fillMedia={false}
              padding="normal"
              horizontalAlign="center"
              verticalAlign="start"
              position="50% 0%"
            >
              <Image
                src="/images/modules/site/enterprise/advanced-security/enterprise-bento-4-visual.webp"
                alt="Screenshot of a failed git push due to the detection of a secret"
                width="471"
                height="128"
                loading="lazy"
                className="lp-borderRadiusNone"
              />
            </Bento.Visual>
          </Bento.Item>

          {/* Bento 5 */}
          <Bento.Item
            columnSpan={{xsmall: 12, medium: 7}}
            rowSpan={{xsmall: 4, medium: 5}}
            style={{
              backgroundSize: 'cover',
              backgroundImage: 'url("/images/modules/site/enterprise/advanced-security/enterprise-bento-5.jpg")',
              gridTemplateRows: 'auto',
              rowGap: '0',
            }}
          >
            <Bento.Content horizontalAlign="center" verticalAlign="end" className="lp-Enterprise-bento5Content">
              <Bento.Heading
                as="h3"
                size="4"
                weight="semibold"
                className="lp-letterSpacing700-whenWide lp-fontSize28-whenNarrow"
              >
                Found means fixed
              </Bento.Heading>
            </Bento.Content>
            <Bento.Visual
              fillMedia={false}
              padding="normal"
              horizontalAlign="center"
              verticalAlign="start"
              position="50% 0%"
            >
              <Image
                src="/images/modules/site/enterprise/advanced-security/enterprise-bento-5-visual.webp"
                alt="Code scanning autofix example that highlights the line of vulnerable code and adds a secure code suggestion"
                width="560"
                height="183"
                loading="lazy"
                className="lp-borderRadiusNone"
              />
            </Bento.Visual>
          </Bento.Item>

          {/* Bento 6 */}
          <Bento.Item
            columnSpan={{xsmall: 12, medium: 5}}
            rowSpan={{xsmall: 3, medium: 5}}
            visualAsBackground
            className="lp-Enterprise-bentoItem"
          >
            <Bento.Content
              horizontalAlign="center"
              verticalAlign="center"
              padding={{xsmall: 'normal', medium: 'spacious'}}
              leadingVisual={<ShieldCheckIcon />}
              className="lp-Bento--withAccentIcon lp-Bento--iconWithThickerStroke"
            >
              <Bento.Heading
                as="h3"
                className="lp-Enterprise-bentoStatsText lp-is-sansSerifAlt lp-letterSpacing700-whenWide"
                style={{marginBottom: '24px', lineHeight: '100%'}}
              >
                <span className="lp-Color-accent">90%</span> <br /> coverage
              </Bento.Heading>
              <Text as="div" variant="muted" style={{marginBottom: '0'}}>
                Copilot Autofix provides code suggestions for 90% of alert types in all supported languages
              </Text>
            </Bento.Content>
          </Bento.Item>

          {/* Bento 7 */}
          <Bento.Item
            columnSpan={12}
            rowSpan={{xsmall: 5, medium: 5}}
            visualAsBackground
            className="lp-Enterprise-bentoItem"
          >
            <Bento.Content
              horizontalAlign="center"
              verticalAlign="center"
              padding={{xsmall: 'normal', medium: 'spacious'}}
            >
              <Bento.Heading
                as="h3"
                size="4"
                weight="semibold"
                className="lp-letterSpacing700-whenWide lp-fontSize22-whenNarrow"
                style={{maxWidth: '840px'}}
              >
                <Image
                  src="/images/modules/site/enterprise/advanced-security/enterprise-bento-7-icon.svg"
                  alt="Telus's logo"
                  width="30"
                  height="24"
                  loading="lazy"
                />
                <div style={{marginBlockStart: '48px', marginBlockEnd: '48px'}}>
                  GitHub Advanced Security helps developers fix potential issues before production.
                </div>
                <Image
                  src="/images/modules/site/enterprise/advanced-security/enterprise-bento-7-logo.svg"
                  alt="Mercado libre's logo"
                  width="157"
                  height="40"
                  loading="lazy"
                />
              </Bento.Heading>
            </Bento.Content>
            <Bento.Visual>
              <Image
                src="/images/modules/site/enterprise/advanced-security/enterprise-bento-7.jpg"
                alt=""
                width="1248"
                height="466"
                loading="lazy"
              />
            </Bento.Visual>
          </Bento.Item>
        </Bento>
      </div>
    </section>
  )
}
