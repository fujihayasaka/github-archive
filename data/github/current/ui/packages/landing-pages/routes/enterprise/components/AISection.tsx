import {Bento, Box, Grid, Image, Link, SectionIntro, Stack, Text, ThemeProvider} from '@primer/react-brand'

import CustomerStoryBento from './CustomerStoryBento'

export default function AISection() {
  return (
    <ThemeProvider colorMode="dark" style={{backgroundColor: 'var(--brand-color-canvas-subtle)'}} id="ai">
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
                    AI
                  </SectionIntro.Label>

                  <SectionIntro.Heading size="1" weight="bold">
                    Build, secure, and ship software faster
                  </SectionIntro.Heading>
                </SectionIntro>

                <Bento>
                  <Bento.Item
                    columnSpan={{
                      xsmall: 12,
                      large: 7,
                    }}
                    rowSpan={{
                      xsmall: 4,
                      large: 5,
                    }}
                    visualAsBackground
                    className="bento-item-ai-copilot"
                  >
                    <Bento.Content
                      padding={{
                        xsmall: 'normal',
                        medium: 'spacious',
                      }}
                    >
                      <Bento.Heading as="h3" size="3" weight="semibold">
                        Push what&apos;s possible with GitHub Copilot, the world&apos;s most trusted and widely adopted
                        AI developer tool.
                      </Bento.Heading>

                      <Link href="/features/copilot" size="large" variant="default">
                        Learn more about Copilot
                      </Link>
                    </Bento.Content>
                  </Bento.Item>

                  <Bento.Item
                    columnSpan={{
                      xsmall: 12,
                      large: 5,
                    }}
                    rowSpan={5}
                    style={{background: 'var(--base-color-scale-black-0)', gridGap: 0}}
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
                        size="display"
                        style={{
                          marginBottom: 'var(--base-size-8)',
                          fontSize: '112px',
                          letterSpacing: '-0.5rem',
                        }}
                      >
                        88%
                      </Bento.Heading>

                      <Text align="center" size="400" weight="normal">
                        of developers experience increased productivity.
                        <sup>
                          <a href="#footnote-1" id="footnote-ref-1">
                            1
                          </a>
                        </sup>
                      </Text>
                    </Bento.Content>

                    <Bento.Visual horizontalAlign="center" verticalAlign="center" padding="spacious" fillMedia={false}>
                      <Image
                        src="/images/modules/site/enterprise/2023/copilot-icon.png"
                        alt="Copilot logo"
                        width="112"
                        height="112"
                      />
                    </Bento.Visual>
                  </Bento.Item>

                  <Bento.Item
                    columnSpan={12}
                    rowSpan={{
                      xsmall: 3,
                      small: 4,
                      medium: 4,
                      large: 5,
                    }}
                    className="bento-item-ai-code"
                  >
                    <Bento.Visual fillMedia={false} horizontalAlign="center" verticalAlign="end">
                      <a
                        href="https://docs.github.com/copilot/quickstart#introduction"
                        data-analytics-event='{"category":"enterprise copilot","action":"click on enterprise copilot","label":"ref_cta:enterprise_copilot;ref_loc:body"}'
                      >
                        <Image
                          src="/images/modules/site/enterprise/2023/code-window.png"
                          alt="Code editor showing code suggestions"
                          className="bento-item-ai-code-img"
                          style={{display: 'block'}}
                        />
                      </a>
                    </Bento.Visual>
                  </Bento.Item>

                  <CustomerStoryBento />
                </Bento>
              </Stack>
            </section>
          </Box>
        </Grid.Column>
      </Grid>
    </ThemeProvider>
  )
}
