import {VerifiedIcon} from '@primer/octicons-react'
import {
  AnimationProvider,
  Bento,
  Heading,
  Image,
  Link,
  River,
  SectionIntro,
  Testimonial,
  Text,
} from '@primer/react-brand'
import FeatureMarqueeAnimation from './FeatureMarqueeAnimation'
import {useEffect, useRef} from 'react'

export default function FeaturesSection() {
  // Animate features testimonial glow on scroll
  // Make sure to only animate a child element to avoid flickering

  const featuresTestimonialAnimationRef = useRef(null)

  useEffect(() => {
    const currentElement = featuresTestimonialAnimationRef.current

    const observer = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add('lp-animateIn')
          } else {
            entry.target.classList.remove('lp-animateIn')
          }
        }
      },
      {
        threshold: 0.5, // Animate once 50% of the height is...
        rootMargin: `0% 0% -33% 0%`, // ...in the top 66% of the viewport
      },
    )

    if (currentElement) {
      observer.observe(currentElement)
    }

    return () => {
      if (currentElement) {
        observer.unobserve(currentElement)
      }
    }
  }, [])

  // Animate enterprise outro lines on scroll

  const enterpriseOutroAnimationRef = useRef(null)

  useEffect(() => {
    const currentElement = enterpriseOutroAnimationRef.current

    const observer = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add('lp-animateIn')
          } else {
            entry.target.classList.remove('lp-animateIn')
          }
        }
      },
      {
        threshold: 0.5, // Animate once 50% of the height is...
        rootMargin: `-15% 0% -15% 0%`, // ...in the center of the viewport
      },
    )

    if (currentElement) {
      observer.observe(currentElement)
    }

    return () => {
      if (currentElement) {
        observer.unobserve(currentElement)
      }
    }
  }, [])

  return (
    <section id="features">
      <div className="lp-Container">
        <div>
          <Image
            src="/images/modules/site/enterprise/advanced-security/features-intro-sm.jpg"
            alt=""
            width={350}
            loading="lazy"
            className="lp-Features-introImage lp-Features-introImage--sm"
          />

          <svg
            fill="none"
            height="332"
            viewBox="0 0 1148 332"
            width="1148"
            aria-hidden="true"
            className="lp-Features-introImage lp-Features-introImage--lg"
            ref={enterpriseOutroAnimationRef}
          >
            <linearGradient id="a" gradientUnits="userSpaceOnUse" x1="579.009" x2="579.009" y1="359.876" y2="-187.685">
              <stop offset=".187774" stopColor="#6bd6d0" />
              <stop offset=".479735" stopColor="#096bde" />
              <stop offset=".658117" stopColor="#000aff" stopOpacity="0" />
            </linearGradient>
            <radialGradient
              id="b"
              cx="0"
              cy="0"
              gradientTransform="matrix(-453.50206521 -223.9968189 134.68107385 -272.67416312 524.499 166.127)"
              gradientUnits="userSpaceOnUse"
              r="1"
            >
              <stop offset=".0229315" stopColor="#6bd6d0" />
              <stop offset=".779747" stopColor="#096bde" />
              <stop offset="1" stopColor="#000aff" />
            </radialGradient>
            <radialGradient
              id="c"
              cx="0"
              cy="0"
              gradientTransform="matrix(492.99945466 -201.99983908 121.45514351 296.42260999 642.501 189)"
              gradientUnits="userSpaceOnUse"
              r="1"
            >
              <stop offset="0" stopColor="#6bd6d0" />
              <stop offset=".659109" stopColor="#096bde" />
              <stop offset="1" stopColor="#000aff" />
            </radialGradient>
            <linearGradient id="d" gradientUnits="userSpaceOnUse" x1="574" x2="574" y1="0" y2="167">
              <stop offset="0" />
              <stop offset="1" stopOpacity="0" />
            </linearGradient>
            <linearGradient id="e" gradientUnits="userSpaceOnUse" x1="1366" x2="1366" y1="540" y2="852">
              <stop offset=".700261" />
              <stop offset="1" stopOpacity="0" />
            </linearGradient>
            <clipPath id="f">
              <path d="m0 0h1148v332h-1148z" />
            </clipPath>
            <g clipPath="url(#f)">
              <path d="m0 0h1148v332h-1148z" fill="#000" />
              <g opacity=".6">
                <g strokeWidth="2.5">
                  <path className="lp-Features-introLine-2" d="m579 291v-343" stroke="url(#a)" />
                  <path
                    className="lp-Features-introLine-1"
                    d="m579.415 519.126v-215.791c0-96.963-78.604-175.567-175.567-175.567h-287.698c-56.793 0-102.7929-46.116-102.6498-102.9091v-228.8589"
                    stroke="url(#b)"
                  />
                  <path
                    className="lp-Features-introLine-3"
                    d="m579.495 519.037v-217.824c0-96.963 78.604-175.567 175.566-175.567h274.289c56.95 0 103.24-45.9545 103.65-102.9089v-232.7371"
                    stroke="url(#c)"
                  />
                </g>
                <path d="m-67 0h1282v167h-1282z" fill="url(#d)" />
                <path d="m970 540h792v312h-792z" fill="url(#e)" transform="matrix(-1 -0 0 -1 1940 1080)" />
              </g>
            </g>
          </svg>
        </div>

        <SectionIntro align="center" className="lp-Features-sectionIntro">
          <SectionIntro.Label className="lp-SectionIntroLabel--muted">Features</SectionIntro.Label>
          <SectionIntro.Heading
            as="h2"
            size="3"
            weight="semibold"
            className="lp-textWrap--balance"
            style={{maxWidth: '32ch'}}
          >
            For developers who love to code.{' '}
            <span className="lp-Color--muted">Detect, prevent, and fix vulnerabilities without leaving your flow.</span>
          </SectionIntro.Heading>
        </SectionIntro>

        <div
          className="lp-Spacer"
          style={{'--lp-space': '28px', '--lp-space-xl': '40px'} as React.CSSProperties}
          aria-hidden
        />

        {/* Features River */}

        <AnimationProvider>
          <River imageTextRatio="60:40" className="lp-River" animate="slide-in-up">
            <River.Content>
              <Heading as="h3" size="5">
                Autofixes anywhere
              </Heading>

              <Text as="p" className="lp-River-text">
                Code scanning with Copilot Autofix detects vulnerabilities, provides contextual explanations, and
                suggests fixes in the pull request and for historical alerts.
              </Text>

              <Link href="https://www.youtube.com/watch?v=mr6vQMDy-YU" target="_blank" variant="default">
                Explore Copilot Autofix
              </Link>
            </River.Content>
            <River.Visual className="lp-River-visual">
              <Image
                src="/images/modules/site/enterprise/advanced-security/features-river-2.webp"
                alt="Code scanning autofix identifies vulnerable code and provides an explanation, together with a secure code suggestion to remediate the vulnerability"
                width="708"
                height="510"
                style={{display: 'block'}}
                loading="lazy"
              />
            </River.Visual>
          </River>

          <River imageTextRatio="60:40" className="lp-River" animate="slide-in-up">
            <River.Content>
              <Heading as="h3" size="5">
                Solve security debt
              </Heading>

              <Text as="p" className="lp-River-text">
                Solve your backlog of application security debt. Security campaigns target and generate autofixes for up
                to 1,000 alerts at a time, rapidly reducing the risk of application vulnerabilities and zero-day
                attacks.
              </Text>
            </River.Content>

            <River.Visual className="lp-River-visual">
              <Image
                src="/images/modules/site/enterprise/advanced-security/features-river-4.webp"
                alt="GitHub push protection confirms an active secret and blocks the push"
                width="708"
                height="510"
                style={{display: 'block'}}
                loading="lazy"
              />
            </River.Visual>
          </River>

          <River imageTextRatio="60:40" className="lp-River" animate="slide-in-up">
            <River.Content>
              <Heading as="h3" size="5">
                Secure your secrets, protect your business
              </Heading>
              <Text as="p" className="lp-River-text">
                Secret scanning with push protection guards over 200 token types and patterns from more than 150 service
                providers, even elusive secrets like passwords and PII.
              </Text>
              <Link
                href="https://docs.github.com/en/enterprise-cloud@latest/code-security/secret-scanning/introduction/about-secret-scanning"
                variant="default"
              >
                Explore secret scanning
              </Link>
            </River.Content>
            <River.Visual className="lp-River-visual">
              <Image
                src="/images/modules/site/enterprise/advanced-security/features-river-3.webp"
                alt="GitHub push protection confirms an active secret and blocks the push"
                width="708"
                height="510"
                style={{display: 'block'}}
                loading="lazy"
              />
            </River.Visual>
          </River>
        </AnimationProvider>

        <div
          className="lp-Spacer"
          style={{'--lp-space': '64px', '--lp-space-xl': '104px'} as React.CSSProperties}
          aria-hidden
        />

        <div className="lp-Features-testimonialWrapper" ref={featuresTestimonialAnimationRef}>
          <div className="lp-Features-testimonialGradientWrapper">
            <div className="lp-Features-testimonialGradient" />
          </div>

          <Testimonial size="large" className="lp-Features-testimonial">
            <Testimonial.Quote className="lp-Features-testimonialQuote">
              Push protection is such a beautiful workflow. We’ve never received a single complaint from developers.
            </Testimonial.Quote>
            <Testimonial.Logo className="lp-Features-testimonialLogo">
              <img
                src="/images/modules/site/enterprise/advanced-security/features-testimonial-logo.svg"
                alt="Telus's logo"
                width="173"
                height="34"
              />
            </Testimonial.Logo>
          </Testimonial>
        </div>

        {/* Features Bento */}

        <Bento className="lp-FeaturesBento--autoHeightWhenNarrow">
          <Bento.Item
            columnSpan={12}
            rowSpan={{xsmall: 5, medium: 6}}
            className="lp-FeaturesBento-item lp-FeaturesBento-item1"
            style={{gridRow: 'auto'}}
          >
            <Bento.Content
              horizontalAlign={{xsmall: 'start', medium: 'center'}}
              verticalAlign="center"
              padding={{xsmall: 'normal', medium: 'spacious'}}
              className="lp-FeaturesBento-content"
            >
              <Bento.Heading as="h3" size="5" weight="semibold">
                Security status at a glance
              </Bento.Heading>
              <Text as="div" variant="muted" style={{maxWidth: '460px'}} className="lp-fontSize--smallWhenNarrow">
                Verify progress and track trends to prioritize remediation tasks across multiple repositories.
              </Text>
              <Link
                href="https://docs.github.com/en/enterprise-cloud@latest/code-security/security-overview/about-security-overview"
                className="lp-Features-linkInBento"
              >
                Discover security overview
              </Link>
            </Bento.Content>
            <Bento.Visual
              position="50% 100%"
              style={{padding: '0 5%'}}
              horizontalAlign="center"
              verticalAlign="end"
              className="lp-FeaturesBento-visual"
            >
              <Image
                as="picture"
                src="/images/modules/site/enterprise/advanced-security/features-bento-1-alt.webp"
                sources={[
                  {
                    srcset: '/images/modules/site/enterprise/advanced-security/features-bento-1-alt-sm.webp',
                    media: '(max-width: 767px)',
                  },
                ]}
                alt="Dependency review identifies high severity vulnerabilities in a .json package"
                loading="lazy"
                className="lp-FeaturesBento-img lp-borderRadiusNone d-block"
              />
            </Bento.Visual>
          </Bento.Item>

          <Bento.Item
            columnSpan={{xsmall: 12, medium: 6}}
            rowSpan={{xsmall: 6, medium: 6}}
            className="lp-FeaturesBento-item"
            style={{gridGap: '0'}}
          >
            <Bento.Content
              horizontalAlign="start"
              verticalAlign="end"
              padding={{xsmall: 'normal', medium: 'spacious'}}
              className="lp-FeaturesBento-content"
            >
              <Bento.Heading as="h3" size="5" weight="semibold">
                Your workflows, <br /> your tools
              </Bento.Heading>
              <Text as="div" variant="muted" className="lp-fontSize--smallWhenNarrow">
                With support for more than 17,000 app integrations and actions templates, GitHub Advanced Security
                provides one workflow for your entire toolchain.
              </Text>
              <Link href="https://github.com/marketplace" className="lp-Features-linkInBento">
                Explore GitHub Marketplace
              </Link>
            </Bento.Content>
            <Bento.Visual>
              <FeatureMarqueeAnimation />
            </Bento.Visual>
          </Bento.Item>

          <Bento.Item
            columnSpan={{xsmall: 12, medium: 6}}
            rowSpan={{xsmall: 5, medium: 6}}
            className="lp-FeaturesBento-item lp-FeaturesBento-item2"
          >
            <Bento.Content
              horizontalAlign="start"
              verticalAlign="end"
              padding={{xsmall: 'normal', medium: 'spacious'}}
              className="lp-FeaturesBento-content"
            >
              <Bento.Heading as="h3" size="5" weight="semibold" style={{maxWidth: '20ch'}}>
                Dependencies you can depend on
              </Bento.Heading>
              <Text as="div" variant="muted" className="lp-fontSize--smallWhenNarrow">
                Secure, manage, and report on software supply chains with automated security, version updates, and
                one-click software bills of material (SBOMs).
              </Text>
              <Link
                href="https://docs.github.com/en/enterprise-cloud@latest/code-security/supply-chain-security/end-to-end-supply-chain/end-to-end-supply-chain-overview"
                className="lp-Features-linkInBento"
              >
                Secure your end-to-end supply chain
              </Link>
            </Bento.Content>
            <Bento.Visual
              fillMedia={false}
              position="0% 0%"
              padding={{xsmall: 'normal', medium: 'spacious'}}
              className="lp-FeaturesBento-visual"
            >
              <Image
                as="picture"
                src="/images/modules/site/enterprise/advanced-security/features-bento-2-alt.webp"
                sources={[
                  {
                    srcset: '/images/modules/site/enterprise/advanced-security/features-bento-2-alt-sm.webp',
                    media: '(max-width: 767px)',
                  },
                ]}
                alt="Trend graph showing a decline in critical vulnerabilities over time"
                loading="lazy"
                className="lp-FeaturesBento-img lp-borderRadiusNone"
              />
            </Bento.Visual>
          </Bento.Item>

          {/* Bento 4 */}
          <Bento.Item
            columnSpan={12}
            rowSpan={{xsmall: 5, medium: 5}}
            flow={{xsmall: 'row', medium: 'column'}}
            className="lp-FeaturesBento-item lp-FeaturesBento-item4"
          >
            <Bento.Content
              horizontalAlign="start"
              verticalAlign="center"
              padding={{xsmall: 'normal', medium: 'spacious'}}
              leadingVisual={<VerifiedIcon />}
              className="lp-FeaturesBento-content lp-FeaturesBento-item4-content lp-Bento--withAccentIcon lp-Bento--iconWithThickerStroke"
            >
              <Bento.Heading as="h3" size="5" weight="semibold" style={{marginTop: 'auto'}}>
                Security expertise at your command
              </Bento.Heading>
              <Text as="p" variant="muted" className="lp-fontSize--smallWhenNarrow">
                Powered by security experts and a global community of more than 100 million developers, GitHub Advanced
                Security provides the insights and automation you need to ship more secure software on schedule.
              </Text>
              <Link href="https://securitylab.github.com/" className="lp-Features-linkInBento">
                Visit the Security Lab
              </Link>
            </Bento.Content>
            <Bento.Visual
              fillMedia={false}
              padding={{xsmall: 'normal', medium: 'spacious'}}
              className="lp-FeaturesBento-visual lp-FeaturesBento-item4-visual"
            >
              <Image
                src="/images/modules/site/enterprise/advanced-security/features-bento-4.webp"
                alt="Insights and remediation advice for a critical Log4j vulnerability as documented in the GitHub Advisory Database"
                width="566"
                height="402"
                loading="lazy"
                className="lp-FeaturesBento-img lp-FeaturesBento-item4-img lp-borderRadiusNone"
              />
            </Bento.Visual>
          </Bento.Item>
        </Bento>
      </div>
    </section>
  )
}
