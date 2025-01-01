import {ContentfulFaqGroup} from '@github-ui/swp-core/components/contentful/ContentfulFaqGroup'
import type {PrimerComponentFaqGroup} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentFaqGroup'

import Styles from './Faq.module.css'

type Props = {
  contentfulContent: PrimerComponentFaqGroup
}

const Faq = ({contentfulContent}: Props) => {
  return (
    <section id="faq" className={Styles['Faq']}>
      <ContentfulFaqGroup component={contentfulContent} />
    </section>
  )
}

export default Faq
