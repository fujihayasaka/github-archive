import {useEffect} from 'react'
import {
  ThemeProvider,
  Hero,
  Image,
  SectionIntro,
  Grid,
  Card,
  Bento,
  Link,
  RiverBreakout,
  Text,
  Timeline,
  CTABanner,
  Button,
  SubNav,
} from '@primer/react-brand'
import {Spacer} from './components/Spacer'

import {featuresData, type Item} from './FeaturesIndex.data'

const renderItemsForSection = (sectionId: string, twoColumns: boolean = false) => {
  const section = featuresData.find(sec => sec.id === sectionId)
  if (!section) return null

  return section.items.map((item: Item, index) => (
    <Grid.Column
      className="lp-Grid-column"
      span={twoColumns ? {xsmall: 12, medium: 6} : {xsmall: 12, medium: 6, large: 4}}
      // eslint-disable-next-line @eslint-react/no-array-index-key
      key={index}
    >
      <Card className="lp-Card fp-gradientBorder" href={item.button_link} fullWidth>
        {item.label && item.label}
        {item.icon && item.icon}
        <Card.Heading size="6">{item.title}</Card.Heading>
        <Card.Description>{item.description}</Card.Description>
      </Card>
    </Grid.Column>
  ))
}

export function FeaturesIndex() {
  // Update selected subnav item while scrolling the page

  useEffect(() => {
    const sections = document.querySelectorAll('section[id]')

    const observer = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          const sectionId = entry.target.id
          const link = document.querySelector(`.lp-SubNav a[href="#${sectionId}"]`)

          if (entry.isIntersecting) {
            link?.setAttribute('aria-current', 'true')

            // Update button label
            const mobileMenuButtonLabel = document.querySelector('.lp-SubNav button span')
            if (mobileMenuButtonLabel && link) {
              mobileMenuButtonLabel.textContent = link.textContent
            }
          } else {
            link?.removeAttribute('aria-current')
          }
        }
      },
      {
        root: null, // Use the viewport as the root
        rootMargin: '0px',
        threshold: 0.05, // Trigger when 5% of the section is visible
      },
    )

    for (const section of sections) observer.observe(section)

    return () => {
      for (const section of sections) observer.unobserve(section)
    }
  }, [])

  // Close menu after clicking on a menu item

  useEffect(() => {
    const subNavElement = document.querySelector('.lp-SubNav') as HTMLElement
    const closeButtonElement = document.querySelector('.lp-SubNav button') as HTMLButtonElement

    if (subNavElement && closeButtonElement && closeButtonElement.ariaExpanded) {
      const handleClick = (event: MouseEvent) => {
        const clickedElement = event.target as HTMLElement
        // Check if the clicked element (or parent) is a link
        if (clickedElement.tagName === 'A' || clickedElement.parentElement?.tagName === 'A') {
          closeButtonElement.click()
        }
      }

      // Add event listener to subNavElement
      subNavElement.addEventListener('click', handleClick)

      // Cleanup function to remove event listener
      return () => {
        subNavElement.removeEventListener('click', handleClick)
      }
    }
  }, [])

  // Add aria-label programmically to the SubNav. Seems not possible to do it via the SubNav component API.

  useEffect(() => {
    const subNavElement = document.querySelector('.lp-SubNav')
    if (subNavElement) {
      subNavElement.setAttribute('aria-label', 'Page section')
    }
  }, [])

  // Animate section intros

  useEffect(() => {
    const intros = document.querySelectorAll('.lp-Intro')

    const observer = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          const introElement = entry.target

          if (entry.isIntersecting) {
            introElement.classList.add('isVisible')
          } else {
            introElement.classList.remove('isVisible')
          }
        }
      },
      {
        root: null, // Use the viewport as the root
        rootMargin: '0px',
        threshold: 1, // Trigger when 100% of the intro is visible
      },
    )

    for (const intro of intros) observer.observe(intro)

    return () => {
      for (const intro of intros) observer.unobserve(intro)
    }
  }, [])

  // Content starts here ------------------------

  return (
    <ThemeProvider colorMode="dark" className="fp-hasFontSmoothing fp-hasDarkGradientBorder fp-animateOnLoad">
      {/* Hero */}

      <section id="hero" className="lp-Section--hero">
        {/* Header + Subnav = 136px */}
        <Spacer size="136px" />
        <Spacer size="48px" size1012="96px" />

        <div className="fp-Section-container">
          <Hero data-hpc align="center" className="fp-Hero">
            <Hero.Heading className="fp-Hero-heading" size="2">
              The tools you need to build
              <br className="d-none d-md-block" /> what you want
            </Hero.Heading>
          </Hero>

          <Spacer size="40px" size1012="80px" />

          <Bento className="lp-Bento">
            <Bento.Item visualAsBackground columnSpan={{xsmall: 12, medium: 6}} rowSpan={{xsmall: 4, xlarge: 3}}>
              <Bento.Content verticalAlign="start" padding={{xsmall: 'normal', small: 'spacious'}}>
                <Bento.Heading as="h2" size="5" weight="semibold">
                  Experience AI with Copilot Chat
                </Bento.Heading>
                <Link href="https://github.com/features/copilot">Learn more</Link>
              </Bento.Content>
              <Bento.Visual>
                <Image
                  className="fp-CopilotChat-Card-image"
                  src="/images/modules/site/features/fp24/hero-bento-1.webp"
                  alt=""
                  width="600"
                />
              </Bento.Visual>
            </Bento.Item>

            <Bento.Item visualAsBackground columnSpan={{xsmall: 12, medium: 6}} rowSpan={{xsmall: 4, xlarge: 3}}>
              <Bento.Content verticalAlign="start" padding={{xsmall: 'normal', small: 'spacious'}}>
                <Bento.Heading as="h2" size="5" weight="semibold">
                  The latest GitHub previews
                </Bento.Heading>
                <Link href="https://github.com/features/preview">Learn more</Link>
              </Bento.Content>
              <Bento.Visual>
                <Image src="/images/modules/site/features/fp24/hero-bento-2.webp" alt="" width="600" />
              </Bento.Visual>
            </Bento.Item>
          </Bento>

          <Spacer size="48px" size1012="96px" />
        </div>
      </section>

      {/* SubNav */}

      <div className="lp-SubNavContainer">
        <SubNav className="lp-SubNav">
          <SubNav.Link href="#features-collaboration">Collaborative coding</SubNav.Link>
          <SubNav.Link href="#features-automation">Automation & CI/CD</SubNav.Link>
          <SubNav.Link href="#features-security">Application security</SubNav.Link>
          <SubNav.Link href="#features-apps">Client apps</SubNav.Link>
          <SubNav.Link href="#features-project-management">Project management</SubNav.Link>
          <SubNav.Link href="#features-team-administration">Governance & administration</SubNav.Link>
          <SubNav.Link href="#features-community">Community</SubNav.Link>
        </SubNav>
      </div>

      {/* Collaboration */}

      <section id="features-collaboration">
        <div className="fp-Section-container">
          <div className="lp-Intro">
            <Image
              className="lp-IntroLine"
              src="/images/modules/site/features/fp24/intro-gitline.svg"
              width={8}
              height={124}
              alt=""
              loading="lazy"
            />
            <Image
              className="lp-IntroVisual"
              width={64}
              height={64}
              src="/images/modules/site/features/fp24/intro-collaboration.webp"
              alt=""
              loading="lazy"
            />
          </div>

          <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
            <SectionIntro.Heading size="3">Collaborative Coding</SectionIntro.Heading>
          </SectionIntro>

          <Spacer size="48px" size1012="96px" />

          <RiverBreakout className="fp-RiverBreakout">
            <RiverBreakout.Visual>
              <Image
                className="fp-RiverBreakoutVisualImage"
                src="/images/modules/site/features/fp24/section-collaboration.webp"
                alt="Screenshot of a code review conversation in GitHub, showing a code change where a line has been edited to include variableDeprecations in addition to versionDeprecations and selectorDeprecations. The change is highlighted, with the old line in red and the new line in green. Below the code, there is a conversation thread with comments from three users, appreciating the catch and expressing satisfaction with the teamwork. The conversation ends with a 'Resolve conversation' button."
                loading="lazy"
              />
            </RiverBreakout.Visual>
            <RiverBreakout.Content
              className="fp-RiverBreakout-content"
              style={{rowGap: '0'}} // Remove gap when 2nd row is unused
              trailingComponent={() => (
                <Timeline>
                  <Timeline.Item>
                    <em>See the changes</em> you care about.
                  </Timeline.Item>
                  <Timeline.Item>
                    <em>Build community</em> around your code.
                  </Timeline.Item>
                </Timeline>
              )}
            >
              <Text className="fp-RiverBreakout-text">
                <em>Innovate faster</em> with
                <br className="d-none d-md-block" /> seamless collaboration.
              </Text>
            </RiverBreakout.Content>
          </RiverBreakout>

          <Spacer size="64px" size1012="96px" />

          <Grid className="lp-Grid">
            {/* Render items */}
            {renderItemsForSection('collaborative_coding')}
          </Grid>
        </div>
      </section>

      {/* Automation */}

      <section id="features-automation">
        <div className="fp-Section-container">
          <div className="lp-Intro">
            <Image
              className="lp-IntroLine"
              src="/images/modules/site/features/fp24/intro-gitline.svg"
              width={8}
              height={124}
              alt=""
              loading="lazy"
            />
            <Image
              className="lp-IntroVisual"
              width={80}
              height={80}
              src="/images/modules/site/features/fp24/intro-automation.webp"
              alt=""
              loading="lazy"
            />
          </div>

          <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
            <SectionIntro.Heading size="3">Automation and CI/CD</SectionIntro.Heading>
          </SectionIntro>

          <Spacer size="48px" size1012="96px" />

          <RiverBreakout className="fp-RiverBreakout">
            <RiverBreakout.Visual>
              <Image
                className="fp-RiverBreakoutVisualImage"
                src="/images/modules/site/features/fp24/section-automation.webp"
                alt="Screenshot of a CI/CD pipeline in GitHub, showing the progress of a build-release workflow. The pipeline includes steps for building on Ubuntu, Windows, and macOS, followed by testing. The production deployment is pending for web-app, web-app-eu, and database, each waiting for additional processes or reviews. The background gradient transitions from blue to green, with a 'Review deployments' button at the top right."
                loading="lazy"
              />
            </RiverBreakout.Visual>
            <RiverBreakout.Content
              className="fp-RiverBreakout-content"
              style={{rowGap: '0'}} // Remove gap when 2nd row is unused
              trailingComponent={() => (
                <Timeline>
                  <Timeline.Item>
                    <em>Standardize and scale</em> best practices, security, and compliance across your organization.
                  </Timeline.Item>
                  <Timeline.Item>
                    <em>Get started quickly with thousands of actions</em> from partners and the community.
                  </Timeline.Item>
                </Timeline>
              )}
            >
              <Text className="fp-RiverBreakout-text">
                <em>Automate everything:</em> CI/CD, testing, planning, project management, issue labeling, approvals,
                onboarding, and more.
              </Text>
            </RiverBreakout.Content>
          </RiverBreakout>

          <Spacer size="64px" size1012="96px" />

          <Grid className="lp-Grid">
            {/* Render items */}
            {renderItemsForSection('automation')}
          </Grid>

          <Spacer size="56px" size1012="112px" />
        </div>
      </section>

      {/* Security */}

      <section id="features-security" className="fp-Section--isRaised lp-Cards--isRaised">
        <div className="fp-Section-container">
          <div className="lp-Intro">
            <Image
              className="lp-IntroLine"
              src="/images/modules/site/features/fp24/intro-gitline.svg"
              width={8}
              height={124}
              alt=""
              loading="lazy"
            />
            <Image
              className="lp-IntroVisual"
              width={64}
              height={64}
              src="/images/modules/site/features/fp24/intro-security.webp"
              alt=""
              loading="lazy"
            />
          </div>

          <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
            <SectionIntro.Heading size="3">Application Security</SectionIntro.Heading>
          </SectionIntro>

          <Spacer size="48px" size1012="96px" />

          <RiverBreakout className="fp-RiverBreakout">
            <RiverBreakout.Visual>
              <Image
                className="fp-RiverBreakoutVisualImage"
                src="/images/modules/site/features/fp24/section-security-illo.webp"
                width="1248"
                height="620"
                alt="Screenshot illustrating GitHub Advanced Security (GHAS) in action. The left side shows a line graph tracking the number of vulnerabilities by severity (Critical, High, Moderate, Low) over time, with data points from January 1 to February 15, 2024. The right side displays a security bot's recommendation to fix a vulnerability in the code. The bot explains that user-provided input is being used in an HTTP response without sanitization, potentially leading to a cross-site scripting (XSS) attack. The AI-suggested fix involves using the escape-html library to sanitize the input, with the old code in red and the new, corrected code in green. The background features a smooth blue gradient."
                loading="lazy"
              />
            </RiverBreakout.Visual>
            <RiverBreakout.Content
              className="fp-RiverBreakout-content"
              style={{rowGap: '0'}} // Remove gap when 2nd row is unused
              trailingComponent={() => (
                <Timeline>
                  <Timeline.Item>
                    <em>Prevent, find, and fix</em> application vulnerabilities and leaked secrets.
                  </Timeline.Item>
                  <Timeline.Item>
                    <em>Target historical alerts</em> to reduce security debt at scale.
                  </Timeline.Item>
                  <Timeline.Item>
                    <em>Built into the GitHub platform</em> that developers know and love.
                  </Timeline.Item>
                </Timeline>
              )}
            >
              <Text className="fp-RiverBreakout-text">
                <em>Application security where found means fixed.</em> Powered by GitHub Copilot Autofix.
              </Text>
              <Link href="/enterprise/advanced-security" className="mt-4" variant="accent">
                Explore GitHub Advanced Security
              </Link>
            </RiverBreakout.Content>
          </RiverBreakout>

          <Spacer size="64px" size1012="96px" />

          <Grid className="lp-Grid">
            {/* Render items */}
            {renderItemsForSection('security')}
          </Grid>

          <Spacer size="64px" size1012="128px" />
        </div>
      </section>

      {/* Client apps */}

      <section id="features-apps">
        <div className="fp-Section-container">
          <div className="lp-Intro">
            <Image
              className="lp-IntroLine"
              src="/images/modules/site/features/fp24/intro-gitline.svg"
              width={8}
              height={124}
              alt=""
              loading="lazy"
            />
            <Image
              className="lp-IntroVisual"
              width={80}
              height={80}
              src="/images/modules/site/features/fp24/intro-apps.webp"
              alt=""
              loading="lazy"
            />
          </div>

          <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
            <SectionIntro.Heading size="3">Client apps</SectionIntro.Heading>
          </SectionIntro>

          <Spacer size="48px" size1012="96px" />

          <RiverBreakout className="fp-RiverBreakout">
            <RiverBreakout.Visual>
              <Image
                className="fp-RiverBreakoutVisualImage"
                src="/images/modules/site/features/fp24/section-apps.webp"
                alt="Screenshot showcasing GitHub across Desktop, Mobile, and Command Line interfaces. The Desktop interface shows a repository with multiple changed files, highlighting app/npm-shrinkwrap.json and a comparison of code changes. The Command Line interface displays the output of the gh pr status command, showing the status of pull requests, with some passing checks and one failing. The Mobile interface on the right side displays the 'Home' screen with options like Issues, Pull Requests, Discussions, and more."
                loading="lazy"
              />
            </RiverBreakout.Visual>
            <RiverBreakout.Content
              className="fp-RiverBreakout-content"
              style={{rowGap: '0'}} // Remove gap when 2nd row is unused
              trailingComponent={() => (
                <Timeline>
                  <Timeline.Item>
                    <em>Accessible anywhere.</em> Use GitHub on macOS, Windows, mobile, or tablet with native apps.
                  </Timeline.Item>
                  <Timeline.Item>
                    <em>Efficient management.</em> Handle pull requests, issues, and tasks swiftly with GitHub CLI or
                    mobile.
                  </Timeline.Item>
                  <Timeline.Item>
                    <em>Streamlined development.</em> Visualize and commit changes easily with GitHub Desktop.
                  </Timeline.Item>
                </Timeline>
              )}
            >
              <Text className="fp-RiverBreakout-text">
                <em>Access GitHub anywhere:</em> On Desktop, Mobile, and Command Line.
              </Text>
            </RiverBreakout.Content>
          </RiverBreakout>

          <Spacer size="64px" size1012="96px" />

          <Grid className="lp-Grid">
            {/* Render items */}
            {renderItemsForSection('client_apps')}
          </Grid>
        </div>
      </section>

      {/* Project Management */}

      <section id="features-project-management">
        <div className="fp-Section-container">
          <div className="lp-Intro">
            <Image
              className="lp-IntroLine"
              src="/images/modules/site/features/fp24/intro-gitline.svg"
              width={8}
              height={124}
              alt=""
              loading="lazy"
            />
            <Image
              className="lp-IntroVisual"
              width={80}
              height={80}
              src="/images/modules/site/features/fp24/intro-project-management.webp"
              alt=""
              loading="lazy"
            />
          </div>

          <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
            <SectionIntro.Heading size="3">Project Management</SectionIntro.Heading>
          </SectionIntro>

          <Spacer size="48px" size1012="96px" />

          <RiverBreakout className="fp-RiverBreakout">
            <RiverBreakout.Visual>
              <Image
                className="fp-RiverBreakoutVisualImage"
                src="/images/modules/site/features/fp24/section-project-management.webp"
                alt="Screenshot of a GitHub Projects board titled 'Product Roadmap,' displaying three columns: Backlog, In Progress, and Triage. Each column contains cards representing issues or tasks, with labels and tags indicating status, priority, iteration, and design requirements. The board features a gradient background transitioning from blue to green."
                loading="lazy"
              />
            </RiverBreakout.Visual>
            <RiverBreakout.Content
              className="fp-RiverBreakout-content"
              style={{rowGap: '0'}} // Remove gap when 2nd row is unused
              trailingComponent={() => (
                <Timeline>
                  <Timeline.Item>
                    <em>Coordinate initiatives big and small</em> with project tables, boards, and task lists.
                  </Timeline.Item>
                  <Timeline.Item>
                    <em>Engineered for software teams.</em>
                  </Timeline.Item>
                  <Timeline.Item>
                    <em>Track what you deliver down to the commit.</em>
                  </Timeline.Item>
                </Timeline>
              )}
            >
              <Text className="fp-RiverBreakout-text">
                <em>Keep feature requests, bugs, and more organized.</em>
              </Text>
            </RiverBreakout.Content>
          </RiverBreakout>

          <Spacer size="64px" size1012="96px" />

          <Grid className="lp-Grid">
            {/* Render items */}
            {renderItemsForSection('project_management')}
          </Grid>
        </div>
      </section>

      {/* Team administration */}

      <section id="features-team-administration">
        <div className="fp-Section-container">
          <div className="lp-Intro">
            <Image
              className="lp-IntroLine"
              src="/images/modules/site/features/fp24/intro-gitline.svg"
              width={8}
              height={124}
              alt=""
              loading="lazy"
            />
            <Image
              className="lp-IntroVisual"
              width={80}
              height={80}
              src="/images/modules/site/features/fp24/intro-team-administration.webp"
              alt=""
              loading="lazy"
            />
          </div>

          <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
            <SectionIntro.Heading size="3">Governance & Administration</SectionIntro.Heading>
          </SectionIntro>

          <Spacer size="48px" size1012="96px" />

          <RiverBreakout className="fp-RiverBreakout">
            <RiverBreakout.Visual>
              <Image
                className="fp-RiverBreakoutVisualImage"
                src="/images/modules/site/features/fp24/section-team-administration.webp"
                alt="Screenshot of a GitHub Team Administration board showing the 'Who has access' section for a private repository. The page displays access levels, including 'Base Role' where all 23 GitHub IAM members have read access, 'Direct Access' for 14 members, and 'Organization Access' for 12 members. The 'Manage access' section below lists individual users with options to create a team, add people, or add a team. Each user entry includes their role, such as 'Write' or 'Read,' along with options to modify their access. The background features a gradient from pink to purple."
                loading="lazy"
              />
            </RiverBreakout.Visual>
            <RiverBreakout.Content
              className="fp-RiverBreakout-content"
              style={{rowGap: '0'}} // Remove gap when 2nd row is unused
              trailingComponent={() => (
                <Timeline>
                  <Timeline.Item>
                    <em>Update permissions, add new users as you grow,</em> and assign everyone the exact permissions
                    they need.
                  </Timeline.Item>
                  <Timeline.Item>
                    <em>Sync with Okta and Entra ID.</em>
                  </Timeline.Item>
                </Timeline>
              )}
            >
              <Text className="fp-RiverBreakout-text">
                <em>Simplify access and permissions management</em> across your projects and teams.
              </Text>
            </RiverBreakout.Content>
          </RiverBreakout>

          <Spacer size="64px" size1012="96px" />

          <Grid className="lp-Grid">
            {/* Render items */}
            {renderItemsForSection('team_administration')}
          </Grid>

          <Spacer size="56px" size1012="112px" />
        </div>
      </section>

      {/* Community */}

      <section id="features-community" className="fp-Section--isRaised lp-Cards--isRaised">
        <div className="fp-Section-container">
          <div className="lp-Intro">
            <Image
              className="lp-IntroLine"
              src="/images/modules/site/features/fp24/intro-gitline.svg"
              width={8}
              height={124}
              alt=""
              loading="lazy"
            />
            <Image
              className="lp-IntroVisual"
              width={80}
              height={80}
              src="/images/modules/site/features/fp24/intro-community.webp"
              alt=""
              loading="lazy"
            />
          </div>

          <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
            <SectionIntro.Heading size="3">Community</SectionIntro.Heading>
          </SectionIntro>

          <Spacer size="48px" size1012="96px" />

          <Image
            className="lp-SectionImage"
            src="/images/modules/site/features/fp24/section-community.webp"
            alt="Screenshot of GitHub Sponsors cards, displaying various open-source projects and individuals available for sponsorship. Each card includes the project or individual's name, an avatar or logo, and a 'Sponsor' button with a heart icon. The background features a gradient transitioning from dark purple to bright orange."
            loading="lazy"
          />

          <Spacer size="64px" size1012="96px" />

          <Grid className="lp-Grid">
            {/* Render items */}
            {renderItemsForSection('community', true)}
          </Grid>

          <Spacer size="56px" size1012="112px" />
        </div>
      </section>

      {/* CTA */}

      <section id="cta">
        <div className="fp-Section-container">
          <Spacer size="64px" size1012="128px" />

          <CTABanner className="lp-CTABanner" align="center" hasShadow={false}>
            <CTABanner.Heading size="2">Ready to get started?</CTABanner.Heading>
            <CTABanner.Description className="lp-CTABannerDescription">
              Explore all the plans to find the solution that fits your needs.
            </CTABanner.Description>
            <CTABanner.ButtonGroup buttonsAs="a">
              <Button href="/pricing">View pricing plans</Button>
            </CTABanner.ButtonGroup>
          </CTABanner>

          <Spacer size="64px" size1012="128px" />
        </div>
      </section>
    </ThemeProvider>
  )
}
