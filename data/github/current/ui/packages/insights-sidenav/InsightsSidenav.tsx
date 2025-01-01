import {PlayIcon, type Icon, PackageIcon, CodeSquareIcon, CopilotIcon, MeterIcon} from '@primer/octicons-react'
import {Heading, Label, NavList} from '@primer/react'
import {testIdProps} from '@github-ui/test-id-props'

import styles from './InsightsSidenav.module.css'
import {clsx} from 'clsx'

export interface InsightsSidenavProps {
  selectedKey?:
    | 'dependency_insights'
    | 'actions_usage_metrics'
    | 'actions_performance_metrics'
    | 'api'
    | 'copilot_metrics_insights'
  /* the show- properties are only needed when something has to be hidden at times (i.e. FF) */
  showDependencies?: boolean
  urls: {[key: string]: string}
  showActionsUsageMetrics?: boolean
  showApi?: boolean
  showCopilotMetricsViewer?: boolean
  showCopilotMetricsCatalog?: boolean
}

export const InsightsSidenav = (props: InsightsSidenavProps) => {
  const navItems: InsightsSideNavItem[] = []

  const actionsPerformanceMetricsKey = `actions_performance_metrics`
  const actionsUsageMetricsKey = `actions_usage_metrics`
  if (props.showActionsUsageMetrics) {
    navItems.push({
      display: 'Actions Usage Metrics',
      key: actionsUsageMetricsKey,
      href: props.urls[actionsUsageMetricsKey] || '#',
      selected: props.selectedKey === actionsUsageMetricsKey,
      icon: PlayIcon,
    })
    navItems.push({
      display: 'Actions Performance Metrics',
      key: actionsPerformanceMetricsKey,
      href: props.urls[actionsPerformanceMetricsKey] || '#',
      selected: props.selectedKey === actionsPerformanceMetricsKey,
      icon: PlayIcon,
    })
  }

  const dependencyKey = 'dependency_insights'
  if (props.showDependencies) {
    navItems.push({
      display: 'Dependencies',
      key: dependencyKey,
      href: props.urls[dependencyKey] || '#',
      selected: props.selectedKey === dependencyKey,
      icon: PackageIcon,
    })
  }

  const apiKey = 'api'
  if (props.showApi) {
    navItems.push({
      display: 'REST API',
      key: apiKey,
      href: props.urls[apiKey] || '#',
      selected: props.selectedKey === apiKey,
      icon: CodeSquareIcon,
      beta: false,
    })
  }

  if (props.showCopilotMetricsViewer && !props.showCopilotMetricsCatalog) {
    const copilotMetricsViewerKey = 'copilot_metrics_insights'
    navItems.push({
      display: 'Copilot user onboarding',
      key: copilotMetricsViewerKey,
      href: props.urls[copilotMetricsViewerKey] || '#',
      selected: props.selectedKey === copilotMetricsViewerKey,
      icon: CopilotIcon,
      beta: false,
    })
  }

  const insightsSideNavElements = (): JSX.Element | JSX.Element[] => {
    const otherInsightsItems = navItems.map(item => {
      return (
        <NavList.Item key={item.key} href={item.href} aria-current={item.selected}>
          <NavList.LeadingVisual>
            <item.icon />
          </NavList.LeadingVisual>
          {item.display}
          {item.beta && (
            <NavList.TrailingVisual>
              <Label variant="success">Preview</Label>
            </NavList.TrailingVisual>
          )}
        </NavList.Item>
      )
    })

    if (props.showCopilotMetricsCatalog) {
      return (
        <>
          <NavList.Group>
            <NavList.Item
              href={props.urls['copilot_metrics_insights']}
              aria-current={props.selectedKey === 'copilot_metrics_insights'}
            >
              <NavList.LeadingVisual>
                <MeterIcon />
              </NavList.LeadingVisual>
              Metrics
            </NavList.Item>
          </NavList.Group>
          <NavList.Group title="Other insights">{otherInsightsItems}</NavList.Group>
        </>
      )
    }

    return otherInsightsItems
  }

  return (
    <div className={styles.InsightsSidenav} {...testIdProps('InsightsSidenav')}>
      <Heading as="h2" variant="medium" sx={{pl: 3}}>
        Insights
      </Heading>
      <NavList aria-label={'Insights navigation'}>{insightsSideNavElements()}</NavList>
    </div>
  )
}

export const InsightsSidenavPanel = (props: InsightsSidenavProps) => {
  return (
    <div className={clsx(styles.InsightsSidenavPanel, 'border-lg-right')}>
      <InsightsSidenav {...props} />
    </div>
  )
}

interface InsightsSideNavItem {
  key: string
  href: string
  display: string
  selected?: boolean
  icon: Icon
  beta?: boolean
}
