import {Bento, Box, Grid, Image, Link, SectionIntro, Stack, ThemeProvider} from '@primer/react-brand'

export default function ReliabilitySection() {
  return (
    <ThemeProvider
      colorMode="light"
      style={{background: '#F8F6F9'}}
      id="reliability"
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
                <SectionIntro className="enterprise-spacer--SectionIntro-Bento" style={{gap: 'var(--base-size-24)'}}>
                  <SectionIntro.Label size="large" className="section-intro-label-custom">
                    Reliability
                  </SectionIntro.Label>

                  <SectionIntro.Heading size="1" weight="bold">
                    90% of the Fortune 100 choose GitHub
                  </SectionIntro.Heading>
                </SectionIntro>

                <Bento>
                  <Bento.Item
                    columnSpan={12}
                    rowSpan={{
                      xsmall: 6,
                      large: 5,
                    }}
                    flow={{
                      xsmall: 'row',
                      medium: 'column',
                    }}
                    colorMode="dark"
                    className="bento-item-reliability-transformation"
                    style={{gridGap: 0}}
                  >
                    <Bento.Content
                      padding={{
                        xsmall: 'normal',
                        medium: 'spacious',
                      }}
                    >
                      <Bento.Heading as="h3" size="3" weight="semibold">
                        Migrate, scale, and use cloud-based compute to accelerate digital transformation.
                      </Bento.Heading>

                      <Link
                        href="https://docs.github.com/migrations/overview/planning-your-migration-to-github"
                        size="large"
                        variant="default"
                      >
                        Explore GitHub Enterprise Importer
                      </Link>
                    </Bento.Content>

                    <Bento.Visual position="16px 0" fillMedia className="bento-visual-reliability-transformation">
                      <Image
                        src="/images/modules/site/enterprise/2023/terminal.png"
                        alt="A terminal showcasing the GitHub CLI"
                      />
                    </Bento.Visual>
                  </Bento.Item>

                  <Bento.Item
                    columnSpan={{xsmall: 12, large: 7}}
                    rowSpan={{
                      xsmall: 4,
                      large: 5,
                    }}
                    colorMode="dark"
                    order="reversed"
                    className="bento-item-reliability-distributed"
                    visualAsBackground
                  >
                    <Bento.Visual position="0% 60%" style={{marginTop: 'auto', maxHeight: '500px'}}>
                      <Image src="/images/modules/site/enterprise/2023/globe.png" alt="An illustration of the globe" />
                    </Bento.Visual>

                    <Bento.Content
                      padding={{
                        xsmall: 'normal',
                        medium: 'spacious',
                      }}
                    >
                      <Bento.Heading as="h3" size="4" weight="semibold">
                        Reliability when it matters most with GitHub’s distributed architecture.
                      </Bento.Heading>
                    </Bento.Content>
                  </Bento.Item>

                  <Bento.Item
                    columnSpan={{xsmall: 12, large: 5}}
                    rowSpan={5}
                    order="reversed"
                    style={{background: 'var(--base-color-scale-white-0)', gridGap: 0}}
                  >
                    <Bento.Content padding="spacious" verticalAlign="end">
                      <Bento.Heading
                        as="h3"
                        size="display"
                        style={{
                          color: 'var(--base-color-scale-purple-7)',
                          marginBottom: 'var(--base-size-8)',
                          fontSize: '96px',
                          letterSpacing: '-0.5rem',
                        }}
                      >
                        75%
                      </Bento.Heading>

                      <Bento.Heading as="h4" size="6" weight="normal" variant="muted" style={{marginBottom: '0'}}>
                        Reduced time spent
                        <br /> managing tools.
                        <sup>
                          <a href="#footnote-2" id="footnote-ref-2">
                            2
                          </a>
                        </sup>
                      </Bento.Heading>
                    </Bento.Content>

                    <Bento.Visual fillMedia={false} padding="spacious">
                      <Image
                        src="/images/modules/site/enterprise/2023/reduce.png"
                        alt="An icon illustrating reduction"
                        width="112"
                        height="112"
                      />
                    </Bento.Visual>
                  </Bento.Item>

                  <Bento.Item
                    columnSpan={12}
                    rowSpan={{
                      xsmall: 6,
                      medium: 5,
                    }}
                    flow={{
                      xsmall: 'row',
                      medium: 'column',
                    }}
                    style={{background: 'var(--base-color-scale-white-0)', gridGap: 0}}
                  >
                    <Bento.Content
                      padding={{
                        xsmall: 'normal',
                        medium: 'spacious',
                      }}
                    >
                      <Bento.Heading as="h3" size="4" weight="semibold">
                        See how Telus saved $16.9 million in costs by replacing their DevOps tools with GitHub.
                      </Bento.Heading>

                      <Link href="/customer-stories/telus" size="large">
                        Read customer story
                      </Link>
                    </Bento.Content>

                    <Bento.Visual padding="normal" position="50% 10%">
                      <Image
                        src="/images/modules/site/enterprise/2023/telus.jpg"
                        alt="A photo of people looking at a tablet"
                      />
                    </Bento.Visual>
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
