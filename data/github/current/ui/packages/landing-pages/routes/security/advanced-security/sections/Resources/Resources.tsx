import {Card, SectionIntro, Stack} from '@primer/react-brand'

import Spacer from '../../components/Spacer/Spacer'

import COPY from './Resources.data'

export default function ResourcesSection() {
  return (
    <section id="resources">
      <div className="lp-Container">
        <SectionIntro align="center" fullWidth style={{padding: '0'}}>
          <SectionIntro.Heading size="3" className="text-wrap-balance">
            Get the most out of GitHub Advanced Security
          </SectionIntro.Heading>
        </SectionIntro>

        <Spacer size="64px" size768="80px" />

        <Stack direction={{narrow: 'vertical', regular: 'horizontal', wide: 'horizontal'}} gap="normal" padding="none">
          {COPY.cards.map((card, index) => (
            // eslint-disable-next-line @eslint-react/no-array-index-key
            <div className="lp-Resources-card" key={`card_${index}`}>
              <Card ctaText={card.link.label} href={card.link.href}>
                <Card.Icon icon={card.icon} color="green" hasBackground />
                <Card.Heading>{card.title}</Card.Heading>
                <Card.Description>{card.description}</Card.Description>
              </Card>
            </div>
          ))}
        </Stack>

        <Spacer size="80px" size768="184px" />
      </div>
    </section>
  )
}
