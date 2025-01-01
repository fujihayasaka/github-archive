import {SectionIntro, Image} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function MobileSection() {
  return (
    <section id="mobile">
      <div className="fp-Section-container">
        <Spacer size="56px" size1012="112px" />

        <SectionIntro className="fp-SectionIntro" align="center">
          <SectionIntro.Heading size="3">Respond on-the-go</SectionIntro.Heading>

          <SectionIntro.Description>
            Converse, check in, and respond to discussions whenever and wherever is convenient for you.
          </SectionIntro.Description>
        </SectionIntro>

        <Spacer size="32px" size1012="64px" />

        <Image
          src="/images/modules/site/discussions/fp24/mobile-1.webp"
          alt="Screenshot of a mobile interface for GitHub Discussions in the 'octoinvaders' project. Featured discussions include 'Game dev log' and 'March game design update.' The page shows categories like Feedback and Show & tell, with active discussions and reactions."
          width={920}
          style={{display: 'block', margin: '0 auto'}}
          loading="lazy"
        />
      </div>
    </section>
  )
}
