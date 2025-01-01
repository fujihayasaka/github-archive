import {Image, SectionIntro, Heading, Link, Text, River} from '@primer/react-brand'

import {COPY} from '../../../Index.data'
import {Spacer} from '../../../../../components/Spacer'

interface FeaturesProps {}

const defaultProps: Partial<FeaturesProps> = {}

const Features: React.FC<FeaturesProps> = props => {
  // eslint-disable-next-line unused-imports/no-unused-vars
  const initializedProps = {...defaultProps, ...props}

  return (
    <section id="features">
      <div className="fp-Section-container">
        <Spacer size="96px" size768="128px" />

        <SectionIntro className="fp-SectionIntro lp-SectionIntro" fullWidth>
          <SectionIntro.Label className="lp-SectionIntro-label">{COPY.features.label}</SectionIntro.Label>
          <SectionIntro.Heading
            size="3"
            // eslint-disable-next-line react/forbid-component-props
            dangerouslySetInnerHTML={{__html: COPY.features.title}}
          />
        </SectionIntro>

        <Spacer size="80px" size768="112px" />

        {COPY.features.items.map((item, index) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <River key={`river_${index}`} className="lp-River" imageTextRatio="60:40">
            <River.Visual className="fp-River-visual lp-River-visual">
              <Image src={item.image.url} alt={item.image.alt} />
            </River.Visual>

            <River.Content>
              <Heading as="h3" size="5">
                {item.title}
              </Heading>
              <Text>{item.description}</Text>
              {item.link ? (
                <Link variant="accent" href={item.link.url}>
                  {item.link.label}
                </Link>
              ) : (
                <></>
              )}
            </River.Content>
          </River>
        ))}
      </div>
    </section>
  )
}

export default Features
