import {SectionIntro, Grid, Pillar} from '@primer/react-brand'
import {NorthStarIcon, StackIcon, ZapIcon} from '@primer/octicons-react'

import {Spacer} from '../components/Spacer'

export default function CardsSection() {
  return (
    <section id="cards">
      <div className="fp-Section-container">
        <Spacer size="56px" size1012="112px" />

        <SectionIntro className="fp-SectionIntro" align="center" fullWidth>
          <SectionIntro.Heading size="3">
            Search, navigate, and understand your <br className="fp-breakWhenWide" /> team’s code—and billions of lines
            of <br className="fp-breakWhenWide" /> public code.
          </SectionIntro.Heading>
        </SectionIntro>

        <Spacer size="40px" size1012="80px" />

        <Grid className="lp-Grid">
          <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 4}}>
            <Pillar>
              <Pillar.Icon color="green" icon={<NorthStarIcon />} />

              <Pillar.Heading>Fast, relevant results</Pillar.Heading>

              <Pillar.Description>
                Code search understands your code—and brings you relevant results with incredible speed.
              </Pillar.Description>
            </Pillar>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 4}}>
            <Pillar>
              <Pillar.Icon color="green" icon={<ZapIcon />} />

              <Pillar.Heading>A power userʼs dream</Pillar.Heading>

              <Pillar.Description>
                Search using regular expressions, boolean operations, keyboard shortcuts, and more.
              </Pillar.Description>
            </Pillar>
          </Grid.Column>

          <Grid.Column className="lp-GridColumn fp-gradientBorder" span={{xsmall: 12, medium: 4}}>
            <Pillar>
              <Pillar.Icon color="green" icon={<StackIcon />} />

              <Pillar.Heading>More than just search</Pillar.Heading>

              <Pillar.Description>
                Dig deeper with the all-new code view—tightly integrating browsing and code navigation.
              </Pillar.Description>
            </Pillar>
          </Grid.Column>
        </Grid>
      </div>
    </section>
  )
}
