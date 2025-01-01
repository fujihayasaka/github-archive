import {COPY, HERO_VISUALS} from './Automation.data'
import SectionTemplate from './components/SectionTemplate/SectionTemplate'
import type Assets from './webgl-utils/assets'

export default function Automation({assetsRef}: {assetsRef: React.RefObject<Assets>}) {
  return (
    <section id="automation" className="lp-Section">
      <SectionTemplate
        intro={{
          mascot: 'copilot',
          title: COPY.intro.title,
          description: COPY.intro.description,
          assetsRef,
          isWebGLMascotOnly: true,
        }}
        hero={{
          visuals: HERO_VISUALS,
          isCopilotUI: true,
          hasPlayButton: true,
          playButtonAriaLabel: COPY.hero.aria.playButton,
        }}
        content={COPY.content}
        customers={COPY.customers}
        accordion={{items: COPY.accordion.items}}
        analyticsId={COPY.analyticsId}
      />
    </section>
  )
}
