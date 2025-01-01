import {useTheme} from '@primer/react'

import type {SystemTemplate} from '../../api/memex/contracts'
import {Link} from '../../router'
import styles from './featured-template-card.module.css'
import {useTemplateLink} from './hooks/use-template-link'

export type FeaturedTemplateCardProps = {
  template: SystemTemplate
}

export function FeaturedTemplateCard({template}: FeaturedTemplateCardProps) {
  const {resolvedColorScheme} = useTheme()
  const to = useTemplateLink({type: 'system', template})
  const imageUrl = resolvedColorScheme === 'dark' ? template.imageUrl.dark : template.imageUrl.light

  return (
    <Link to={to} className={styles.cardContainerStyles}>
      <div className={styles.imageContainerStyles}>
        <img src={imageUrl} alt="" className={styles.templateImageStyles} />
      </div>
      <div className={styles.templateInfoStyles}>
        <div>
          <span className={styles.Box_4}>{template.title}</span>
          <span className={styles.Box_5}> &bull; {'GitHub'}</span>
          {template.shortDescription && <p className={styles.Box_6}>{template.shortDescription}</p>}
        </div>
      </div>
    </Link>
  )
}
