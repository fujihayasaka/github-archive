import {GraphIcon} from '@primer/octicons-react'
import {Heading} from '@primer/react'

import {LoadingBox} from './loading-box'
import styles from './no-data-card.module.css'

export const NoDataCard = () => {
  return (
    <LoadingBox>
      <GraphIcon className="fgColor-muted" size="medium" />
      <Heading as="h3" className={styles.Heading}>
        No data available
      </Heading>
      <p className={styles.Box}>No results were returned.</p>
    </LoadingBox>
  )
}
