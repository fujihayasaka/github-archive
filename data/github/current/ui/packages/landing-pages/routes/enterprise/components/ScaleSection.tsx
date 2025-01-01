import {
  AnimationProvider,
  Box,
  Grid,
  Heading,
  Image,
  Link,
  River,
  SectionIntro,
  Stack,
  Testimonial,
  Text,
  ThemeProvider,
} from '@primer/react-brand'

export default function ScaleSection() {
  return (
    <ThemeProvider colorMode="dark" id="scale" className="enterprise-dark-bg">
      <Box
        paddingBlockStart={{
          regular: 32,
        }}
        paddingBlockEnd={{
          narrow: 64,
          regular: 128,
        }}
        className="overflow-hidden"
      >
        <Grid>
          <Grid.Column>
            <section className="enterprise-center-until-medium">
              <Stack padding="none">
                <Grid>
                  <Grid.Column span={{xlarge: 10}}>
                    <SectionIntro
                      fullWidth
                      className="enterprise-spacer--SectionIntro-River"
                      style={{gap: 'var(--base-size-24)'}}
                    >
                      <SectionIntro.Label size="large" className="section-intro-label-custom">
                        Scale
                      </SectionIntro.Label>

                      <SectionIntro.Heading size="1" weight="bold">
                        The enterprise-ready platform that developers know and love
                      </SectionIntro.Heading>
                    </SectionIntro>
                  </Grid.Column>
                </Grid>

                <AnimationProvider runOnce>
                  <River imageTextRatio="60:40" animate="slide-in-down">
                    <River.Visual className="enterprise-river-visual">
                      <a
                        href="https://docs.github.com/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning"
                        data-analytics-event='{"category":"enterprise consolidate","action":"click on enterprise consolidate","label":"ref_cta:enterprise_consolidate;ref_loc:body"}'
                      >
                        <Image
                          src="/images/modules/site/enterprise/2023/devops.png"
                          alt="A notification panel from a development operations tool showing statuses such as 'Changes requested,' 'Some checks were not successful,' and 'Merging is blocked."
                        />
                      </a>
                    </River.Visual>

                    <River.Content>
                      <Heading size="5" as="h3" weight="medium">
                        Consolidate DevSecOps processes and enable unparalleled collaboration.
                      </Heading>

                      <Link href="https://resources.github.com/forrester/" variant="accent">
                        Learn more about the ROI of GitHub
                      </Link>
                    </River.Content>
                  </River>

                  <River imageTextRatio="60:40" animate="slide-in-down">
                    <River.Visual className="enterprise-river-visual">
                      <a
                        href="https://github.com/marketplace"
                        data-analytics-event='{"category":"enterprise secure","action":"click on enterprise secure","label":"ref_cta:enterprise_secure;ref_loc:body"}'
                      >
                        <Image
                          src="/images/modules/site/enterprise/2023/platform.png"
                          alt="A collection of application icons for various development tools like Imgbot, AccessLint, WakaTime, Circle CI, Cirrus CI and Code Climate."
                        />
                      </a>
                    </River.Visual>

                    <River.Content
                      trailingComponent={() => (
                        <div className="pr-lg-10">
                          <hr className="enterprise-separator mb-6 mt-n3" />

                          <Heading as="h4" size="3">
                            17,000+
                          </Heading>

                          <Text as="p" size="300" weight="light" variant="muted">
                            Third-party tools support your favorite languages and frameworks
                          </Text>
                        </div>
                      )}
                    >
                      <Heading size="5" as="h3" weight="medium">
                        Leverage the industry’s most flexible secure development platform.
                      </Heading>
                    </River.Content>
                  </River>

                  <River imageTextRatio="60:40" animate="slide-in-down">
                    <River.Visual className="enterprise-river-visual">
                      <a
                        href="https://docs.github.com/copilot/github-copilot-chat/about-github-copilot-chat#about-github-copilot-chat"
                        data-analytics-event='{"category":"enterprise ai","action":"click on enterprise ai","label":"ref_cta:enterprise_ai;ref_loc:body"}'
                      >
                        <Image
                          src="/images/modules/site/enterprise/2023/ai.png"
                          alt="A user interface element with a search bar inviting to 'Ask a question or type '/' for topics'."
                        />
                      </a>
                    </River.Visual>

                    <River.Content>
                      <Heading size="5" as="h3" weight="medium">
                        Unlocking innovation at scale with AI-driven software development.
                      </Heading>
                    </River.Content>
                  </River>
                </AnimationProvider>
              </Stack>
            </section>
          </Grid.Column>
        </Grid>

        <Box className="position-relative">
          <Grid>
            <Grid.Column>
              <AnimationProvider runOnce>
                <Box
                  animate="slide-in-down"
                  padding={{
                    narrow: 24,
                    regular: 96,
                    wide: 128,
                  }}
                  marginBlockStart={64}
                  className="position-relative z-1 testimonial-glass"
                >
                  <Testimonial size="large" quoteMarkColor="purple">
                    <Testimonial.Quote>
                      We’ve used GitHub from the inception of Datadog. It’s a high-quality product,{' '}
                      <Text variant="muted" size="600">
                        and a lot of our engineers contribute to open source so there’s a sense of community there.
                        GitHub is ingrained in the DNA of our engineering, it’s become part of the culture.”
                      </Text>
                    </Testimonial.Quote>

                    <Testimonial.Avatar
                      src="/images/modules/site/enterprise/2023/avatar-emilio.png"
                      alt="Emilio Escobar's avatar"
                    />

                    <Testimonial.Name
                      position="Chief Information Security Officer @ Datadog"
                      className="enterprise-testimonial-name"
                    >
                      Emilio Escobar
                    </Testimonial.Name>
                  </Testimonial>
                </Box>
              </AnimationProvider>
            </Grid.Column>
          </Grid>

          <Image
            src="/images/modules/site/enterprise/2023/element-1.png"
            alt="Decorative element"
            width="634"
            height="634"
            className="position-absolute testimonial-element-1 d-none d-md-block"
          />

          <Image
            src="/images/modules/site/enterprise/2023/element-2.png"
            alt="Decorative element"
            width="766"
            height="788"
            className="position-absolute testimonial-element-2"
          />
        </Box>
      </Box>
    </ThemeProvider>
  )
}
