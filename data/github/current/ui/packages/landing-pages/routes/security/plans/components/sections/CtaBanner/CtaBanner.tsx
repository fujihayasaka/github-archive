import {ContentfulCtaBanner} from '@github-ui/swp-core/components/contentful/ContentfulCtaBanner'
import type {PrimerComponentCtaBanner} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentCtaBanner'

import Styles from './CtaBanner.module.css'

type Props = {
  contentfulContent: PrimerComponentCtaBanner
}

const CtaBanner = ({contentfulContent}: Props) => {
  return (
    <section className={Styles['CtaBanner']}>
      <div className={Styles['CtaBanner__container']}>
        <ContentfulCtaBanner component={contentfulContent} />
      </div>
    </section>
  )
}

export default CtaBanner
