import {ChevronDownIcon, XIcon} from '@primer/octicons-react'
import {Box, Button, Heading, SectionIntro, Stack, Text, UnorderedList} from '@primer/react-brand'
import {useState} from 'react'

interface PricingSectionProps {
  pricingContactSalesPath: string
}

export default function PricingSection({pricingContactSalesPath}: PricingSectionProps) {
  const [expandedStates, setExpandedStates] = useState<{[key: string]: boolean}>({})
  const isDetailsExpanded = (id: string) => {
    return expandedStates[id]
  }

  const toggleDetailsExpanded = (e: React.MouseEvent<HTMLElement>) => {
    const id = (e.target as HTMLElement).getAttribute('data-target-id')
    if (!id) return
    setExpandedStates(prev => ({...prev, [id]: !prev[id]}))
  }

  return (
    <section id="pricing" className="lp-Section--pricing">
      <div className="lp-Container">
        <div className="lp-Spacer--pricing" aria-hidden />

        <SectionIntro align="center" fullWidth>
          <SectionIntro.Label className="lp-SectionIntroLabel--muted">Pricing</SectionIntro.Label>
          <SectionIntro.Heading as="h2" size="2">
            Enable native security <br /> for every repository
          </SectionIntro.Heading>
          <SectionIntro.Description className="lp-Pricing-sectionIntroDescription">
            Eliminate toolchain cost and complexity with native DevSecOps tools for
            <br className="lp-break-whenMedium" /> GitHub Enterprise and Azure DevOps.
          </SectionIntro.Description>
        </SectionIntro>

        <div className="lp-Spacer" style={{'--lp-space': '40px'} as React.CSSProperties} aria-hidden />

        <Stack
          className="lp-Pricing-card"
          direction={{narrow: 'vertical', regular: 'horizontal'}}
          gap="none"
          padding="none"
        >
          {/* Standard */}

          <Stack padding="none" gap={{narrow: 16, regular: 24}} style={{flex: '1'}}>
            <Box>
              <Text size="100" weight="semibold" className="lp-Pricing-label">
                Included with all plans
              </Text>
              <Box marginBlockStart={8} marginBlockEnd={16}>
                <Heading as="h3" size="5">
                  Standard security
                </Heading>
              </Box>
              <Text as="p" size="200" weight="normal" variant="muted" className="lp-Pricing-description">
                Manage and secure open source components and public repositories
              </Text>
            </Box>

            <Box>
              <Stack direction="horizontal" gap={8} padding="none" className="lp-Pricing-price">
                <Text size="500" weight="normal" className="lp-is-sansSerifAlt" style={{lineHeight: 1.3}}>
                  $
                </Text>
                <Text weight="normal" className="lp-is-sansSerifAlt" style={{fontSize: '56px', lineHeight: 1}}>
                  0
                </Text>
                <Text
                  size="500"
                  weight="normal"
                  className="lp-is-sansSerifAlt"
                  style={{lineHeight: 1.1, alignSelf: 'end', marginLeft: '8px'}}
                >
                  USD
                </Text>
              </Stack>
              <Text as="div" size="200" weight="normal" variant="muted" style={{marginTop: '8px'}}>
                For all users and plans
              </Text>
            </Box>

            <Button as="a" href="https://docs.github.com/code-security/getting-started/github-security-features" block>
              Learn more
            </Button>

            <hr className="lp-Pricing-divider" />

            <div>
              <Text size="100" weight="semibold" variant="muted" className="lp-Pricing-listTitle">
                What’s included:
              </Text>

              <button
                type="button"
                aria-expanded={isDetailsExpanded('standard')}
                data-target-id="standard"
                className="position-relative text-semibold lp-Pricing-features-toggle-btn mb-0 mb-md-3 d-md-none"
                onClick={toggleDetailsExpanded}
              >
                What&apos;s included
                <span className="lp-Pricing-features-icon position-absolute top-0 right-0 bottom-0">
                  <ChevronDownIcon />
                </span>
              </button>

              <div className="lp-Pricing-features-box">
                <Text size="100" weight="semibold" variant="muted" className="lp-Pricing-groupTitle">
                  Code scanning
                </Text>

                <UnorderedList variant="checked" className="lp-Pricing-list">
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Code scanning with Copilot Autofix for public
                    repositories
                  </UnorderedList.Item>
                </UnorderedList>

                <UnorderedList className="lp-Pricing-list lp-Pricing-list--excluded" aria-label="What’s not included:">
                  <UnorderedList.Item>
                    <XIcon />
                    <span className="sr-only">Not included, </span>
                    Autofixes in pull requests and for existing alerts
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <XIcon />
                    <span className="sr-only">Not included, </span>
                    Contextual vulnerability intelligence and advice
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <XIcon />
                    <span className="sr-only">Not included, </span>
                    Hunt zero-day threats and their variants
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <XIcon />
                    <span className="sr-only">Not included, </span>
                    Solve security debt with security campaigns
                  </UnorderedList.Item>
                </UnorderedList>

                <Text size="100" weight="semibold" variant="muted" className="lp-Pricing-groupTitle">
                  Secret scanning
                </Text>
                <UnorderedList variant="checked" className="lp-Pricing-list">
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Find secrets in public repositories only
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Block secrets on pushes to public repositories
                  </UnorderedList.Item>
                </UnorderedList>
                <UnorderedList className="lp-Pricing-list lp-Pricing-list--excluded" aria-label="What’s not included:">
                  <UnorderedList.Item>
                    <XIcon />
                    <span className="sr-only">Not included, </span>
                    Revoke and notify on leaked secrets
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <XIcon />
                    <span className="sr-only">Not included, </span>
                    Copilot Secret Scanning**
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <XIcon />
                    <span className="sr-only">Not included, </span>
                    Find elusive secrets like PII and passwords**
                  </UnorderedList.Item>
                </UnorderedList>

                <Text size="100" weight="semibold" variant="muted" className="lp-Pricing-groupTitle">
                  Supply chain
                </Text>
                <UnorderedList variant="checked" className="lp-Pricing-list">
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Identify and update vulnerable open source components
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Access intelligence in the GitHub Advisory Database
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Report vulnerabilities to open source maintainers
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Generate and export SBOMs
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Manage transitive dependencies with submission API
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Detect calls to vulnerable functions (public
                    repositories)
                  </UnorderedList.Item>
                </UnorderedList>
                <UnorderedList className="lp-Pricing-list lp-Pricing-list--excluded" aria-label="What’s not included:">
                  <UnorderedList.Item>
                    <XIcon />
                    <span className="sr-only">Not included, </span>
                    Define and enforce auto-triage rules
                  </UnorderedList.Item>
                </UnorderedList>

                <Text size="100" weight="semibold" variant="muted" className="lp-Pricing-groupTitle">
                  Administration
                </Text>

                <UnorderedList className="lp-Pricing-list lp-Pricing-list--excluded" aria-label="What’s not included:">
                  <UnorderedList.Item>
                    <XIcon />
                    <span className="sr-only">Not included, </span>
                    View security metrics and insights
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <XIcon />
                    <span className="sr-only">Not included, </span>
                    Assess feature adoption and code security risk
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <XIcon />
                    <span className="sr-only">Not included, </span>
                    Enable security features for multiple repositories
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <XIcon />
                    <span className="sr-only">Not included, </span>
                    Define and manage security campaigns**
                  </UnorderedList.Item>
                </UnorderedList>
              </div>
            </div>
          </Stack>

          <hr className="lp-Pricing-divider lp-Pricing-divider--vertical" />

          {/* Advanced */}

          <Stack padding="none" gap={{narrow: 16, regular: 24}} style={{flex: '1'}}>
            <Box>
              <Text size="100" weight="semibold" className="lp-Pricing-label">
                Requires GitHub Enterprise or Azure DevOps
              </Text>
              <Box marginBlockStart={8} marginBlockEnd={16}>
                <Heading as="h3" size="5">
                  GitHub Advanced Security
                </Heading>
              </Box>
              <Text as="p" size="200" weight="normal" variant="muted" className="lp-Pricing-description">
                Detect, prevent, and remediate vulnerabilities in all public and private repositories
              </Text>
            </Box>

            <Box>
              <Stack direction="horizontal" gap={8} padding="none" className="lp-Pricing-price">
                <Text size="500" weight="normal" className="lp-is-sansSerifAlt" style={{lineHeight: 1.3}}>
                  $
                </Text>
                <Text weight="normal" className="lp-is-sansSerifAlt" style={{fontSize: '56px', lineHeight: 1}}>
                  49
                </Text>
                <Text
                  size="500"
                  weight="normal"
                  className="lp-is-sansSerifAlt"
                  style={{lineHeight: 1.1, alignSelf: 'end', marginLeft: '8px'}}
                >
                  USD
                </Text>
              </Stack>
              <Text as="div" size="200" weight="normal" variant="muted" style={{marginTop: '8px'}}>
                per month / per active committer
              </Text>
            </Box>

            <Button as="a" href={pricingContactSalesPath} variant="primary">
              Contact sales
            </Button>

            <hr className="lp-Pricing-divider" />

            <div>
              <Text size="100" weight="semibold" variant="muted" className="lp-Pricing-listTitle">
                What’s included:
              </Text>

              <button
                type="button"
                aria-expanded={isDetailsExpanded('advanced')}
                data-target-id="advanced"
                className="position-relative text-semibold lp-Pricing-features-toggle-btn mb-0 mb-md-3 d-md-none"
                onClick={toggleDetailsExpanded}
              >
                What&apos;s included
                <span className="lp-Pricing-features-icon position-absolute top-0 right-0 bottom-0">
                  <ChevronDownIcon />
                </span>
              </button>

              <div className="lp-Pricing-features-box">
                <Text size="100" weight="semibold" variant="muted" className="lp-Pricing-groupTitle">
                  Code scanning
                </Text>

                <UnorderedList variant="checked" className="lp-Pricing-list">
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Code scanning with Copilot Autofix for private and public
                    repositories
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Autofixes in pull requests and for existing alerts
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Contextual vulnerability intelligence and advice
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Hunt zero-day threats and their variants
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Solve security debt with security campaigns
                  </UnorderedList.Item>
                </UnorderedList>

                <Text size="100" weight="semibold" variant="muted" className="lp-Pricing-groupTitle">
                  Secret scanning
                </Text>

                <UnorderedList variant="checked" className="lp-Pricing-list">
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Find secrets in public and private repositories
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Block secrets on pushes to public and private
                    repositories
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Revoke and notify on leaked secrets
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Copilot Secret Scanning**
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Find elusive secrets like PII and passwords**
                  </UnorderedList.Item>
                </UnorderedList>

                <Text size="100" weight="semibold" variant="muted" className="lp-Pricing-groupTitle">
                  Supply chain
                </Text>
                <UnorderedList variant="checked" className="lp-Pricing-list">
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Identify and update vulnerable open source components
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Access intelligence in the GitHub Advisory Database
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Report vulnerabilities to open source maintainers
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Generate and export SBOMs
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Manage transitive dependencies with submission API
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Detect calls to vulnerable functions (all repositories)
                  </UnorderedList.Item>
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Define and enforce auto-triage rules
                  </UnorderedList.Item>
                </UnorderedList>

                <Text size="100" weight="semibold" variant="muted" className="lp-Pricing-groupTitle">
                  Administration
                </Text>

                <UnorderedList variant="checked" className="lp-Pricing-list">
                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>View security metrics and insights
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Assess feature adoption and code security risk
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Enable security features for multiple repositories
                  </UnorderedList.Item>

                  <UnorderedList.Item>
                    <span className="sr-only">Included, </span>Define and manage security campaigns**
                  </UnorderedList.Item>
                </UnorderedList>

                <Text size="100" variant="muted" className="lp-Pricing-footnote">
                  ** Only with GitHub Advanced Security on GitHub Enterprise Cloud
                </Text>
              </div>
            </div>
          </Stack>
        </Stack>
      </div>
    </section>
  )
}
