import {GraphIcon} from '@primer/octicons-react'
import {Heading} from '@primer/react'

import {LoadingBox} from './loading-box'
import styles from './loading-card.module.css'

export const LoadingCard = () => {
  return (
    <LoadingBox>
      <GraphIcon className="fgColor-muted" size="medium" />
      <Heading as="h3" className={styles.Heading}>
        Loading <span className="AnimatedEllipsis" />
      </Heading>
    </LoadingBox>
  )
}
