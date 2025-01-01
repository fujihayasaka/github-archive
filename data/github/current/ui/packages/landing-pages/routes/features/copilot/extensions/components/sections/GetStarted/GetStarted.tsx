import {SectionIntro} from '@primer/react-brand'
import {useRef} from 'react'

import {COPY} from '../../../Index.data'
import Cards from '../../Cards/Cards'
import {Spacer} from '../../../../../components/Spacer'
import useIntersectionObserver from '../../../../../../../lib/hooks/useIntersectionObserver'

interface GetStartedProps {}

const defaultProps: Partial<GetStartedProps> = {}

const GetStarted: React.FC<GetStartedProps> = props => {
  // eslint-disable-next-line unused-imports/no-unused-vars
  const initializedProps = {...defaultProps, ...props}

  const sectionIntroRef = useRef<HTMLDivElement>(null)

  const {isIntersecting: isSectionIntroInView} = useIntersectionObserver(sectionIntroRef, {
    threshold: 1,
    isOnce: true,
  })

  return (
    <section id="resources">
      <div className="fp-Section-container">
        <Spacer size="96px" size768="128px" />

        <div ref={sectionIntroRef}>
          <SectionIntro
            className={`fp-SectionIntro lp-SectionIntro ${!isSectionIntroInView ? 'lp-SectionIntro--hidden' : ''}`}
          >
            <SectionIntro.Label className="lp-SectionIntro-label">{COPY.getStarted.label}</SectionIntro.Label>
            <SectionIntro.Heading
              size="3"
              // eslint-disable-next-line react/forbid-component-props
              dangerouslySetInnerHTML={{__html: COPY.getStarted.title}}
            />
          </SectionIntro>
        </div>

        <Spacer size="80px" size768="80px" />

        <Cards items={COPY.getStarted.cards} />
      </div>
    </section>
  )
}

export default GetStarted
