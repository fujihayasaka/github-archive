import {Box} from '@primer/react-brand'
import {ContentfulStatistic} from '@github-ui/swp-core/components/contentful/ContentfulStatistic'
import type {PrimerComponentStatistic} from '@github-ui/swp-core/schemas/contentful/contentTypes/primerComponentStatistic'

import styles from './StatisticsGroup.module.css'

type StatisticsGroupProps = {
  statistics: PrimerComponentStatistic[]
  className?: string
  position: 'hero' | 'body'
  headingElementSize?: 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6'
}

export const StatisticsGroup = ({statistics, headingElementSize, position}: StatisticsGroupProps) => {
  return (
    <Box
      className={position === 'body' ? `${styles.statisticsGroup} ${styles.body}` : styles.statisticsGroup}
      paddingBlockEnd={{narrow: 96, regular: 96}}
    >
      {statistics.map(stat => (
        <div
          key={stat.sys.id}
          className={position === 'body' ? `${styles.statisticWrapper} ${styles.body}` : styles.statisticWrapper}
        >
          <ContentfulStatistic component={stat} headingElementSize={headingElementSize} animate="fade-in" />
        </div>
      ))}
    </Box>
  )
}
