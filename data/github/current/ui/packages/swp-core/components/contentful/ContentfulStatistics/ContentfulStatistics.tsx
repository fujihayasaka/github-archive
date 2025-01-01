import {ContentfulStatistic} from '../ContentfulStatistic/ContentfulStatistic'
import type {PrimerStatistics} from '../../../schemas/contentful/contentTypes/primerStatistics'
import {Grid} from '@primer/react-brand'
import styles from './ContentfulStatistics.module.css'

/**
 * Uses TypeScript discriminated union to ensure the component accepts either a `component`
 * or a `statistics` prop, but not both. This increases the flexibility
 * of this component by supporting either a primerStatistics entry or a
 * plain array of primerComponentStatistic entries.
 */
export type ContentfulStatisticsProps =
  | {
      component: PrimerStatistics
      statistics?: never
      className?: string
      statisticBgColor?: 'default' | 'subtle'
    }
  | {
      statistics: PrimerStatistics['fields']['statistics']
      component?: never
      className?: string
      statisticBgColor?: 'default' | 'subtle'
    }

export function ContentfulStatistics({component, statistics, className, statisticBgColor}: ContentfulStatisticsProps) {
  const collection = component !== undefined ? component.fields.statistics : statistics

  // We enforce a minimum of 3 statistics and a maximum of 4 in Contentful. This will ensure that the statistics will
  // span the entire width of the Grid.
  const largeSpan = collection.length === 3 ? 4 : 3

  return (
    <Grid className={className} fullWidth>
      {collection.map(statistic => (
        <Grid.Column span={{medium: 6, large: largeSpan}} key={statistic.sys.id}>
          <ContentfulStatistic
            key={statistic.sys.id}
            component={statistic}
            bgColor={statisticBgColor}
            className={styles.statistic}
          />
        </Grid.Column>
      ))}
    </Grid>
  )
}
