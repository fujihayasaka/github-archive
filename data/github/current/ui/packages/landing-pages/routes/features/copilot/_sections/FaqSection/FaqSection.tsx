import {Grid} from '@primer/react-brand'

import {ContentfulFaqGroup} from '@github-ui/swp-core/components/contentful/ContentfulFaqGroup'
import type {PrimerComponentFaqGroup} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentFaqGroup'

import type {GenericSectionWithIds} from '../../../../../brand/lib/types/contentful'

type Props = {
  contentfulContent: GenericSectionWithIds
}

export function FaqSection(props: Props) {
  const {contentfulContent} = props

  const faqComponent = contentfulContent.fields.content?.find(
    item => item.sys.contentType.sys.id === 'primerComponentFaqGroup',
  ) as PrimerComponentFaqGroup | undefined

  return (
    <section id="faq" className="lp-Section pb-8 pb-md-12 pt-8 pt-md-12">
      <Grid>
        <Grid.Column span={12} className="lp-FAQs">
          {faqComponent ? <ContentfulFaqGroup component={faqComponent} /> : null}
        </Grid.Column>
      </Grid>
    </section>
  )
}
