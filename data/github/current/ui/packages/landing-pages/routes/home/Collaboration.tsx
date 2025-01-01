import {COPY, HERO_VISUALS} from './Collaboration.data'
import SectionTemplate from './components/SectionTemplate/SectionTemplate'
import type Assets from './webgl-utils/assets'

export default function Collaboration({assetsRef}: {assetsRef: React.RefObject<Assets>}) {
  return (
    <section id="collaboration" className="lp-Section">
      <SectionTemplate
        intro={{
          mascot: 'mona',
          title: COPY.intro.title,
          description: COPY.intro.description,
          assetsRef,
          isWebGLMascotOnly: true,
        }}
        hero={{visuals: HERO_VISUALS}}
        content={COPY.content}
        testimonial={COPY.testimonial}
        accordion={{items: COPY.accordion.items}}
        analyticsId={COPY.analyticsId}
      />
    </section>
  )
}
