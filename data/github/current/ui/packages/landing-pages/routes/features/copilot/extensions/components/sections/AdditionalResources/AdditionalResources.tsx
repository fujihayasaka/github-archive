import {SectionIntro} from '@primer/react-brand'

import {COPY} from '../../../Index.data'
import Cards from '../../Cards/Cards'
import {Spacer} from '../../../../../components/Spacer'

interface AdditionalResourcesProps {}

const defaultProps: Partial<AdditionalResourcesProps> = {}

const AdditionalResources: React.FC<AdditionalResourcesProps> = props => {
  // eslint-disable-next-line unused-imports/no-unused-vars
  const initializedProps = {...defaultProps, ...props}

  return (
    <section id="additional-resources">
      <div className="fp-Section-container">
        <Spacer size="96px" size768="128px" />

        <SectionIntro className="fp-SectionIntro lp-SectionIntro lp-SectionIntro--resources" fullWidth>
          <SectionIntro.Heading
            as="h2"
            size="3"
            // eslint-disable-next-line react/forbid-component-props
            dangerouslySetInnerHTML={{__html: COPY.resources.title}}
          />
        </SectionIntro>

        <Spacer size="40px" size768="80px" />

        <Cards items={COPY.resources.cards} />
      </div>
    </section>
  )
}

export default AdditionalResources
