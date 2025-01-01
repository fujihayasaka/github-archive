import {ThemeProvider, Image, Text, Timeline, RiverBreakout, Bento, AnimationProvider} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function FeaturesBento() {
  return (
    <section id="features-2">
      <ThemeProvider
        colorMode="dark"
        className="fp-hasDarkGradientBorder"
        style={{backgroundColor: 'var(--brand-color-canvas-default'}}
      >
        <div className="fp-Section-container">
          <Spacer size="64px" size1012="128px" />

          <RiverBreakout className="fp-RiverBreakout">
            <RiverBreakout.A11yHeading as="h2">Features</RiverBreakout.A11yHeading>

            <RiverBreakout.Visual>
              <Image
                className="fp-RiverBreakoutVisualImage"
                src="/images/modules/site/issues/fp24/features-river-breakout.webp"
                alt="Screenshot of a project management dashboard showing tasks organized by milestone for the 'OctoArcade Invaders' project, with tasks grouped under categories like 'Engine,' 'Game Loop,' and 'Art’ with a light purple to pink background gradient."
                loading="lazy"
              />
            </RiverBreakout.Visual>

            <RiverBreakout.Content
              className="fp-RiverBreakout-content"
              trailingComponent={() => (
                <Timeline>
                  <Timeline.Item>
                    <em>Save views for sprints, backlogs, teams, or releases.</em>
                    Rank, group, sort, slice and filter to suit the occasion. Create swimlanes, share templates and set
                    work in progress limits.
                  </Timeline.Item>

                  <Timeline.Item>
                    <em>No mouse? No problem.</em> Every action you can take with the mouse has a keyboard shortcut or
                    command. Filter, sort, group, and assign issues. Your hands never leave the keyboard.
                  </Timeline.Item>
                </Timeline>
              )}
            >
              <Text style={{maxWidth: '520px'}}>
                <em>Bored of boards?</em> Switch to tables and roadmaps. Create views for how you work.
              </Text>
            </RiverBreakout.Content>
          </RiverBreakout>

          <Spacer size="64px" size1012="128px" />

          <AnimationProvider staggerDelayIncrement={50}>
            <Bento className="lp-Bento">
              <Bento.Item
                className="lp-BentoItem lp-BentoItem1 fp-gradientBorder"
                columnSpan={12}
                flow={{large: 'column'}}
              >
                <Bento.Content className="lp-BentoItem-content" verticalAlign="center">
                  <Bento.Heading as="h3" size="5" weight="semibold" animate="slide-in-up">
                    Extend issues with <br className="fp-breakWhenWide" /> custom fields
                  </Bento.Heading>

                  <Text as="p" size="200" style={{marginBottom: 0}} animate="slide-in-up">
                    Track metadata like iterations, priority, story points, dates, notes, and links. Add custom fields
                    to projects and edit from the issue sidebar.
                  </Text>
                </Bento.Content>

                <Bento.Visual className="lp-BentoItem-visual" fillMedia={false}>
                  <Image
                    src="/images/modules/site/issues/fp24/features-bento-1.webp"
                    alt="Table view of task assignments, showing assignees, labels like 'Bug,' 'Need help,' and 'Design,' and the corresponding work cycles for each task."
                    width="566"
                    loading="lazy"
                  />
                </Bento.Visual>
              </Bento.Item>

              <Bento.Item className="lp-BentoItem lp-BentoItem2 fp-gradientBorder" columnSpan={{xsmall: 12, large: 6}}>
                <Bento.Content className="lp-BentoItem-content">
                  <Bento.Heading as="h3" size="5" weight="semibold" animate="slide-in-up">
                    Track progress with <br className="fp-breakWhenWide" /> project insights
                  </Bento.Heading>

                  <Text as="p" size="200" style={{marginBottom: 0}} animate="slide-in-up">
                    Track the health of your current iteration cycle, milestone, or any other custom field you create
                    with new project insights. Identify bottlenecks and issues blocking the team from making progress
                    with the new burn up chart.
                  </Text>
                </Bento.Content>

                <Bento.Visual className="lp-BentoItem-visual" fillMedia={false}>
                  <Image
                    src="/images/modules/site/issues/fp24/features-bento-2.webp"
                    alt="A chart shows project progress from July 5, 2023. The purple line marks 91 completed tasks, the green line shows 74 open tasks, and the gray line indicates 8 not planned tasks. The chart helps track progress and spot bottlenecks."
                    width="548"
                    loading="lazy"
                  />
                </Bento.Visual>
              </Bento.Item>

              <Bento.Item className="lp-BentoItem lp-BentoItem3 fp-gradientBorder" columnSpan={{xsmall: 12, large: 6}}>
                <Bento.Content className="lp-BentoItem-content">
                  <Bento.Heading as="h3" size="5" weight="semibold" animate="slide-in-up">
                    Share best practices with <br className="fp-breakWhenWide" /> project templates
                  </Bento.Heading>

                  <Text as="p" size="200" style={{marginBottom: 0}} animate="slide-in-up">
                    Create templates to share and reuse when getting started with a new project. Share inspiration
                    across teams and get started with a single click.
                  </Text>
                </Bento.Content>

                <Bento.Visual className="lp-BentoItem-visual" fillMedia={false}>
                  <Image
                    src="/images/modules/site/issues/fp24/features-bento-3.webp"
                    alt="A project planning interface showing tasks related to the 'Kickoff' phase, all currently marked as 'Todo.' Tasks include confirming roles, verifying attendees, and reviewing the communication plan."
                    width="547"
                    loading="lazy"
                  />
                </Bento.Visual>
              </Bento.Item>

              <Bento.Item className="lp-BentoItem lp-BentoItem4 fp-gradientBorder" columnSpan={12}>
                <Bento.Content className="lp-BentoItem-content">
                  <Bento.Heading as="h3" size="5" weight="semibold" animate="slide-in-up">
                    Manage work automatically
                  </Bento.Heading>

                  <Text as="p" size="200" style={{marginBottom: 0, maxWidth: '460px'}} animate="slide-in-up">
                    Accelerate your project planning with workflows. Automatically triage issues, set values for custom
                    fields, and auto add or archive issues.
                  </Text>
                </Bento.Content>

                <Bento.Visual
                  className="lp-BentoItem-visual"
                  fillMedia={false}
                  horizontalAlign="center"
                  padding={{xsmall: 'normal', medium: 'spacious'}}
                >
                  <Image
                    src="/images/modules/site/issues/fp24/features-bento-4.webp"
                    alt="An automated workflow system showcasing triggers and actions. When an issue or pull request is opened, it is added to a project. When an issue is closed, it is archived. When a code review is approved, the status is set to 'ready to merge'."
                    width="1002"
                    loading="lazy"
                  />
                </Bento.Visual>
              </Bento.Item>
            </Bento>
          </AnimationProvider>

          <Spacer size="64px" size1012="128px" />
        </div>
      </ThemeProvider>
    </section>
  )
}
