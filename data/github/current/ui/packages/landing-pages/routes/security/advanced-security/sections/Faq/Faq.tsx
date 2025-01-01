import {ContentfulFaqGroup} from '@github-ui/swp-core/components/contentful/ContentfulFaqGroup'
import type {PrimerComponentFaqGroup} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentFaqGroup'

import Spacer from '../../components/Spacer/Spacer'
import Styles from './Faq.module.css'

type Props = {
  contentfulContent: PrimerComponentFaqGroup
}

export default function FaqSection({contentfulContent}: Props) {
  return (
    <section id="faq" className={Styles.Faq}>
      <div className="lp-Container">
        <Spacer size="80px" size768="128px" />

        <ContentfulFaqGroup component={contentfulContent} />

        <Spacer size="80px" size768="128px" />
      </div>
    </section>
  )
}
