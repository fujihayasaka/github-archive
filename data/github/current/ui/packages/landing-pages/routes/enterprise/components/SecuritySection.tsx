import {Bento, Box, Grid, Image, Label, Link, SectionIntro, Stack, Text, ThemeProvider} from '@primer/react-brand'

export default function SecuritySection() {
  return (
    <ThemeProvider
      colorMode="light"
      style={{background: 'var(--base-color-scale-gray-1)'}}
      id="security"
      className="enterprise-section-rounded"
    >
      <Grid>
        <Grid.Column>
          <Box
            paddingBlockStart={{
              narrow: 64,
              regular: 128,
            }}
            paddingBlockEnd={{
              narrow: 64,
              regular: 128,
            }}
            marginBlockEnd={{
              narrow: 32,
              regular: 64,
            }}
          >
            <section className="enterprise-center-until-medium">
              <Stack padding="none" gap="spacious">
                <SectionIntro
                  align="center"
                  className="enterprise-spacer--SectionIntro-Bento"
                  style={{gap: 'var(--base-size-24)'}}
                >
                  <SectionIntro.Label size="large" className="section-intro-label-custom">
                    Security
                  </SectionIntro.Label>

                  <SectionIntro.Heading size="1" weight="bold">
                    Efficiency and security at every step
                  </SectionIntro.Heading>
                </SectionIntro>

                <Bento>
                  <Bento.Item
                    columnSpan={12}
                    rowSpan={{
                      xsmall: 5,
                      medium: 6,
                      large: 7,
                    }}
                    colorMode="dark"
                    className="bento-item-security-ci-cd"
                    style={{gridGap: 0}}
                  >
                    <Bento.Content
                      padding={{
                        xsmall: 'normal',
                        medium: 'spacious',
                      }}
                      horizontalAlign="center"
                    >
                      <Bento.Heading
                        as="h3"
                        size="3"
                        weight="semibold"
                        className="text-center"
                        style={{maxWidth: '660px'}}
                      >
                        Deliver secure software fast, with enterprise-ready CI/CD, using GitHub Actions.
                      </Bento.Heading>

                      <Link href="/solutions/ci-cd/" size="large" variant="default">
                        Learn more about CI/CD
                      </Link>
                    </Bento.Content>

                    <Bento.Visual fillMedia={false} position="50% 100%" style={{padding: '0 5%'}}>
                      <Image src="/images/modules/site/enterprise/2023/ci-cd.png" alt="CI/CD interface" />
                    </Bento.Visual>
                  </Bento.Item>

                  <Bento.Item
                    columnSpan={{xsmall: 12, medium: 5}}
                    rowSpan={{
                      xsmall: 4,
                      large: 5,
                    }}
                  >
                    <Bento.Content padding="spacious" verticalAlign="center">
                      <Bento.Heading
                        as="h3"
                        size="4"
                        weight="semibold"
                        className="text-center width-full"
                        style={{color: 'var(--base-color-scale-blue-5)', marginBottom: '0'}}
                      >
                        <Box
                          marginBlockEnd={{
                            narrow: 36,
                            regular: 36,
                            wide: 64,
                          }}
                        >
                          <Image
                            src="/images/modules/site/enterprise/2023/time.png"
                            alt="Time icon"
                            width="110"
                            height="110"
                            style={{objectFit: 'contain'}}
                          />
                        </Box>
                        Found means fixed
                      </Bento.Heading>
                    </Bento.Content>
                  </Bento.Item>

                  <Bento.Item
                    columnSpan={{xsmall: 12, medium: 7}}
                    rowSpan={{xsmall: 4, large: 5}}
                    colorMode="dark"
                    className="bento-item-security-end-to-end"
                  >
                    <Bento.Content padding={{xsmall: 'normal', medium: 'spacious'}} horizontalAlign="center">
                      <Bento.Heading
                        as="h3"
                        size="4"
                        weight="semibold"
                        className="text-center"
                        style={{maxWidth: '580px'}}
                      >
                        Keep vulnerabilities out of code and solve security debt
                      </Bento.Heading>

                      <Link href="/enterprise/advanced-security" size="large" variant="default">
                        Explore GitHub Advanced Security
                      </Link>
                    </Bento.Content>

                    <Bento.Visual position="0 0" style={{paddingLeft: 'var(--base-size-24)'}}>
                      <Image
                        src="/images/modules/site/enterprise/2024/security-copilot-autofix.png"
                        alt="UI of workflow runs"
                      />
                    </Bento.Visual>
                  </Bento.Item>

                  <Bento.Item
                    columnSpan={{xsmall: 12, large: 7}}
                    rowSpan={4}
                    colorMode="dark"
                    visualAsBackground
                    style={{background: '#0057cf'}}
                  >
                    <Bento.Content padding={{xsmall: 'normal', medium: 'spacious'}} horizontalAlign={'center'}>
                      <Bento.Heading as="h3" size="6" weight="semibold" className="mb-4">
                        <Label>
                          <span style={{paddingTop: '2px', display: 'block'}}>GitHub Enterprise Cloud</span>
                        </Label>
                      </Bento.Heading>

                      <Text as="p" size="600" weight="semibold" style={{color: '#ffffff'}}>
                        Enhanced control <br />
                        with data residency
                        <sup>
                          <a href="#footnote-2" id="footnote-ref-2" style={{color: 'inherit'}}>
                            2
                          </a>
                        </sup>
                      </Text>

                      <Link
                        href="https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/about-github-enterprise-cloud-with-data-residency"
                        size="large"
                        variant="default"
                        className="mt-0"
                      >
                        Learn more
                      </Link>
                    </Bento.Content>

                    <Bento.Visual position="0 0">
                      <Image
                        src="/images/modules/site/enterprise/2024/security-enterprise-cloud.webp"
                        alt=""
                        aria-hidden="true"
                      />
                    </Bento.Visual>
                  </Bento.Item>

                  {/* visualAsBackground is needed to ensure vertical spacing, even if there's no visual */}
                  {/* See this bug https://github.com/primer/brand/issues/792 */}
                  <Bento.Item
                    columnSpan={{xsmall: 12, large: 5}}
                    rowSpan={4}
                    colorMode="dark"
                    style={{background: 'var(--base-color-scale-green-5, #238636)'}}
                    visualAsBackground
                  >
                    <Bento.Content padding={{xsmall: 'normal', medium: 'spacious'}}>
                      <Bento.Heading as="h3" size="4" weight="semibold">
                        See how DVAG puts customers first by optimizing developer efficiency and security.
                      </Bento.Heading>

                      <Link href="/customer-stories/dvag" size="large" variant="default">
                        Read customer story
                      </Link>
                    </Bento.Content>
                  </Bento.Item>
                </Bento>
              </Stack>
            </section>
          </Box>
        </Grid.Column>
      </Grid>
    </ThemeProvider>
  )
}
