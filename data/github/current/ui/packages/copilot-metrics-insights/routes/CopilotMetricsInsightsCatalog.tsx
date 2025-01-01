import styles from './CopilotMetricsInsightsCatalog.module.css'
import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemDescriptionItem} from '@github-ui/list-view/ListItemDescriptionItem'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {ListItemTrailingBadge} from '@github-ui/list-view/ListItemTrailingBadge'
import {Heading} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
interface MetricsCatalogEntry {
  name: string
  description: string
  category: string
  path: string
}
interface CatalogPayload {
  dashboards: MetricsCatalogEntry[]
}

export function CopilotMetricsInsightsCatalog() {
  const {dashboards} = useRoutePayload<CatalogPayload>()

  function pluralize(word: string, count: number) {
    return count === 1 ? word : `${word}s`
  }

  return (
    <div>
      <Heading as="h1" variant="medium" className={styles.InsightsCatalogHeading}>
        Metrics
      </Heading>
      <ListView
        title="Metrics Insights Catalog"
        className={styles.InsightsListView}
        data-testid="insights-catalog-list-view"
        metadata={<ListViewMetadata title={`${dashboards?.length} ${pluralize('Metric', dashboards?.length)}`} />}
      >
        {dashboards?.map(dashboard => (
          <ListItem
            key={dashboard.name}
            className={styles.InsightsCatalogListItem}
            title={
              <ListItemTitle
                value={dashboard.name}
                trailingBadges={[<ListItemTrailingBadge key={0} title={dashboard.category} />]}
                href={dashboard.path}
              />
            }
          >
            <ListItemMainContent>
              <ListItemDescription>
                <ListItemDescriptionItem>{dashboard.description}</ListItemDescriptionItem>
              </ListItemDescription>
            </ListItemMainContent>
          </ListItem>
        ))}
      </ListView>
    </div>
  )
}
