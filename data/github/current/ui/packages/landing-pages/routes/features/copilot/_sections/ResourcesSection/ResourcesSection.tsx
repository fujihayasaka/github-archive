import {Grid} from '@primer/react-brand'

import {ContentfulSectionIntro} from '@github-ui/swp-core/components/contentful/ContentfulSectionIntro'
import {ContentfulCards} from '@github-ui/swp-core/components/contentful/ContentfulCards'
import type {PrimerCards} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerCards'

import type {GenericSectionWithIds} from '../../../../../brand/lib/types/contentful'

type Props = {
  contentfulContent: GenericSectionWithIds
}

export function ResourcesSection(props: Props) {
  const {contentfulContent} = props
  const {sectionIntro, content} = contentfulContent.fields

  const cardsComponent =
    (content?.find(item => item.sys.contentType.sys.id === 'primerCards') as PrimerCards) || undefined

  return (
    <section id="resources" className="lp-Resources-wrapper">
      <Grid className="lp-Section-container--centerUntilMedium lp-Grid--noRowGap lp-Resources-container pb-8 pb-md-12 pt-8 pt-md-12">
        <Grid.Column span={12}>
          {sectionIntro ? (
            <ContentfulSectionIntro component={sectionIntro} fullWidth headingSize="3" className="lp-SectionIntro" />
          ) : null}

          {cardsComponent ? (
            <ContentfulCards component={cardsComponent} className="lp-Resources-card" fullWidth />
          ) : null}
        </Grid.Column>
      </Grid>
    </section>
  )
}
