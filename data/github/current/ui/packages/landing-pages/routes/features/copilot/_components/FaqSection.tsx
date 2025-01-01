import {Grid} from '@primer/react-brand'

import {ContentfulFaqGroup} from '@github-ui/swp-core/components/contentful/ContentfulFaqGroup'
import type {PrimerComponentFaqGroup} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentFaqGroup'

type Props = {
  contentfulContent: PrimerComponentFaqGroup
}

export default function FaqSection({contentfulContent}: Props) {
  return (
    <section id="faq" className="lp-Section lp-Section--level-1">
      <Grid>
        <Grid.Column span={12} className="lp-FAQs">
          <ContentfulFaqGroup component={contentfulContent} />
        </Grid.Column>
      </Grid>
    </section>
  )
}
