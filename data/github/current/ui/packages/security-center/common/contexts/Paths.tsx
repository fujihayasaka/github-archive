import {encodePart, orgOnboardingAdvancedSecurityPath, type PathFunction} from '@github-ui/paths'
import {createContext, useContext} from 'react'

import type {GroupingType} from '../../overview-dashboard/components/alert-trends-chart/grouping-type'
import type {PeriodOptions} from '../utils/date-period'

export const alertTrendsEndpointSuffixes = [
  'age',
  'severity',
  'tool-code-scanning',
  'tool-dependabot-alerts',
  'tool-secret-scanning',
] as const
export type AlertTrendsEndpointSuffix = (typeof alertTrendsEndpointSuffixes)[number]

type CardQueryParams = {
  startDate: string
  endDate: string
  query: string
  slice4?: string
}

type AlertTrendsQueryParams = CardQueryParams & {
  alertState: 'open' | 'closed'
  grouping: GroupingType
}

interface OverviewPaths {
  advisoriesPath: PathFunction<CardQueryParams>
  ageOfAlertsPath: PathFunction<CardQueryParams>
  alertActivityPath: PathFunction<CardQueryParams>
  alertTrendsPath: PathFunction<AlertTrendsQueryParams>
  alertsFixedWithAutofixPath: PathFunction<CardQueryParams>
  historicalAlertsFixedWithAutofixPath: PathFunction<CardQueryParams>
  introducedAndPreventedPath: PathFunction<CardQueryParams>
  csvExportPath: PathFunction<CardQueryParams>
  meanTimeToRemediatePath: PathFunction<CardQueryParams>
  netResolveRatePath: PathFunction<CardQueryParams>
  pullRequestAlertsFixedPath: PathFunction<CardQueryParams>
  reopenedAlertsPath: PathFunction<CardQueryParams>
  repositoriesPath: PathFunction<CardQueryParams>
  sastPath: PathFunction<CardQueryParams>
  secretsBypassedPath: PathFunction<CardQueryParams>
  onboardingAdvancedSecurityPath: PathFunction
}

interface EnablementTrendsReportPaths {
  enablementTrendsPath: PathFunction<CardQueryParams>
}

type CodeScanningReportParams = {
  startDate: string
  endDate: string
  query: string
}

type DependabotReportParams = {
  query: string
  startDate?: string
  endDate?: string
  funnelOrder?: string
}

type PageParams = {
  cursor?: string
  pageSize?: number
}

type SortParams = {
  sortField?: string
  sortDirection?: 'asc' | 'desc'
}

type CodeScanningMetricsParams = {period?: PeriodOptions; query: string} | CardQueryParams
interface CodeScanningReportPaths {
  codeScanningMetricsPath: PathFunction<CodeScanningMetricsParams>
  codeScanningAlertsFoundPath: PathFunction<CodeScanningReportParams>
  codeScanningAutofixSuggestionsPath: PathFunction<CodeScanningReportParams>
  codeScanningAlertsFixedPath: PathFunction<CodeScanningReportParams>
  codeScanningAlertTrendsPath: PathFunction<CodeScanningReportParams & {groupKey: 'status' | 'severity'}>
  codeScanningAlertsFixedWithAutofixPath: PathFunction<CodeScanningReportParams>
  codeScanningRemediationRatesPath: PathFunction<CodeScanningReportParams>
  codeScanningRemediationTimePath: PathFunction<CodeScanningReportParams>
  codeScanningMostPrevalentRulesPath: PathFunction<CodeScanningReportParams & PageParams>
  codeScanningRepositoriesPath: PathFunction<CodeScanningReportParams & PageParams & SortParams>
  codeScanningCsvExportPath: PathFunction<CodeScanningReportParams>
}

type DependabotMetricsParams = {period?: PeriodOptions; query: string} | CardQueryParams
interface DependabotReportPaths {
  dependabotMetricsPath: PathFunction<DependabotMetricsParams>
  dependabotAlertsFixedPath: PathFunction<DependabotReportParams>
  dependabotAlertTrendsPath: PathFunction<DependabotReportParams>
  dependabotAlertsListPath: PathFunction<{query: string}>
  dependabotRepositoriesPath: PathFunction<DependabotReportParams & PageParams & SortParams>
}

type SecretScanningMetricsParams = {period?: PeriodOptions; query: string} | CardQueryParams

type SecretScanningAlertCentricViewParams = {
  query: string
}

interface SecretScanningReportPaths {
  secretScanningMetricsPath: PathFunction<SecretScanningMetricsParams>
  secretsPushProtectionMetricsPath: PathFunction<CardQueryParams>
  secretsPushProtectionBlocksByTokenTypeMetricsPath: PathFunction<CardQueryParams>
  secretsPushProtectionBlocksByRepositoryMetricsPath: PathFunction<CardQueryParams>
  secretsPushProtectionBypassesByTokenTypeMetricsPath: PathFunction<CardQueryParams>
  secretsPushProtectionBypassesByRepositoryMetricsPath: PathFunction<CardQueryParams>
  secretScanningAlertCentricViewPath: PathFunction<SecretScanningAlertCentricViewParams>
}

type SuggestionsQueryParams =
  | {
      type:
        | 'repos'
        | 'teams'
        | 'tools'
        | 'topics'
        | 'owners'
        | 'orgs'
        | 'secret-scanning.secret-types'
        | 'secret-scanning.providers'
        | 'codeql.rules'
        | 'third-party.rules'
        | 'dependabot.ecosystems'
        | 'dependabot.packages'
    }
  | {type: 'props'; name: string}
export interface Paths
  extends OverviewPaths,
    EnablementTrendsReportPaths,
    CodeScanningReportPaths,
    DependabotReportPaths,
    SecretScanningReportPaths {
  suggestionsPath: PathFunction<SuggestionsQueryParams>
}

export const PathsContext = createContext<Paths | undefined>(undefined)

export const usePaths = (): Paths => {
  const context = useContext(PathsContext)

  if (context == null) {
    throw new Error('usePaths must be used within a PathsProvider')
  }

  return context
}

const toSearchParams = (params: Record<string, string | number | undefined>): URLSearchParams => {
  return Object.entries(params).reduce((result, [key, value]) => {
    if (value != null) {
      result.set(key, value.toString())
    }
    return result
  }, new URLSearchParams())
}

export class OrgPaths implements Paths {
  private declare org: string
  constructor(org: string) {
    this.org = org
  }

  private rootPath: PathFunction = () => `/orgs/${encodePart(this.org)}`

  // #region Options
  suggestionsPath: PathFunction<SuggestionsQueryParams> = props => {
    const {type} = props
    let path = `${this.rootPath()}/security/options?options-type=${type}`
    if (type === 'props') {
      path += `&name=${props.name}`
    }

    return path
  }
  // #endregion

  // #region Overview
  advisoriesPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/advisories?${new URLSearchParams(params).toString()}`
  }

  ageOfAlertsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/age-of-alerts?${new URLSearchParams(params).toString()}`
  }

  alertActivityPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/alert-activity?${new URLSearchParams(params).toString()}`
  }

  introducedAndPreventedPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/introduced-prevented?${new URLSearchParams(params).toString()}`
  }

  alertTrendsPath: PathFunction<AlertTrendsQueryParams> = ({alertState, grouping, query, ...rest}) => {
    const isOpenSelected = alertState !== 'closed'
    const params = new URLSearchParams({
      'alertTrendsChart[isOpenSelected]': isOpenSelected.toString(),
      query,
      ...rest,
    })

    let endpointSuffix: AlertTrendsEndpointSuffix = 'tool-code-scanning'
    switch (grouping) {
      case 'age':
        endpointSuffix = 'age'
        break
      case 'severity':
        endpointSuffix = 'severity'
        break
      case 'tool':
        if (query.includes('dependabot')) {
          endpointSuffix = 'tool-dependabot-alerts'
        } else if (query.includes('secret-scanning')) {
          endpointSuffix = 'tool-secret-scanning'
        }
        break
    }

    return `${this.rootPath()}/security/overview/alert-trends-by-${endpointSuffix}?${params.toString()}`
  }

  alertsFixedWithAutofixPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/alerts-fixed-with-autofix?${new URLSearchParams(params).toString()}`
  }

  historicalAlertsFixedWithAutofixPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/historical-alerts-fixed-with-autofix?${new URLSearchParams(
      params,
    ).toString()}`
  }

  csvExportPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/export?${new URLSearchParams(params).toString()}`
  }

  meanTimeToRemediatePath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/mean-time-to-remediate?${new URLSearchParams(params).toString()}`
  }

  netResolveRatePath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/net-resolve-rate?${new URLSearchParams(params).toString()}`
  }

  pullRequestAlertsFixedPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/pull-request-alerts-fixed?${new URLSearchParams(params).toString()}`
  }

  reopenedAlertsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/reopened-alerts?${new URLSearchParams(params).toString()}`
  }

  repositoriesPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/repositories?${new URLSearchParams(params).toString()}`
  }

  sastPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/sast?${new URLSearchParams(params).toString()}`
  }

  secretsBypassedPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/secrets-bypassed?${new URLSearchParams(params).toString()}`
  }
  // #endregion

  // #region Enablement trends report
  enablementTrendsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/metrics/enablement/enablement-trends?${new URLSearchParams(params).toString()}`
  }
  // #endregion

  // #region Code Scanning report
  codeScanningMetricsPath: PathFunction<CodeScanningMetricsParams> = params =>
    `${this.rootPath()}/security/metrics/codeql?${toSearchParams(params).toString()}`

  codeScanningAlertsFoundPath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/alerts-found?${toSearchParams(params).toString()}`

  codeScanningAutofixSuggestionsPath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/autofix-suggestions?${toSearchParams(params).toString()}`

  codeScanningAlertsFixedPath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/alerts-fixed?${toSearchParams(params).toString()}`

  codeScanningAlertTrendsPath: PathFunction<CodeScanningReportParams & {groupKey: 'status' | 'severity'}> = ({
    groupKey,
    ...rest
  }) => {
    return `${this.rootPath()}/security/metrics/codeql/alert-trends-by-${groupKey}?${toSearchParams(rest)}`
  }

  codeScanningAlertsFixedWithAutofixPath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/alerts-fixed-with-autofix?${toSearchParams(params).toString()}`

  codeScanningRemediationRatesPath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/remediation-rates?${toSearchParams(params).toString()}`

  codeScanningRemediationTimePath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/remediation-time?${toSearchParams(params).toString()}`

  codeScanningMostPrevalentRulesPath: PathFunction<CodeScanningReportParams & PageParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/most-prevalent-rules?${toSearchParams(params).toString()}`

  codeScanningRepositoriesPath: PathFunction<CodeScanningReportParams & PageParams & SortParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/repositories?${toSearchParams(params).toString()}`

  codeScanningCsvExportPath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/export?${toSearchParams(params).toString()}`
  // #endregion

  // #region Dependabot report
  dependabotMetricsPath: PathFunction<DependabotMetricsParams> = params =>
    `${this.rootPath()}/security/metrics/dependabot?${toSearchParams(params).toString()}`

  dependabotAlertsFixedPath: PathFunction<DependabotReportParams> = params =>
    `${this.rootPath()}/security/metrics/dependabot/alerts-fixed?${toSearchParams(params).toString()}`

  dependabotAlertTrendsPath: PathFunction<DependabotReportParams> = params =>
    `${this.rootPath()}/security/metrics/dependabot/alerts-funnel?${toSearchParams(params).toString()}`

  dependabotAlertsListPath: PathFunction<{query: string}> = ({query}) =>
    `${this.rootPath()}/security/alerts/dependabot?q=${encodeURIComponent(query)}`

  dependabotRepositoriesPath: PathFunction<DependabotReportParams & PageParams & SortParams> = params =>
    `${this.rootPath()}/security/metrics/dependabot/repositories?${toSearchParams(params).toString()}`
  // #endregion

  // #region Secret Scanning report
  secretScanningMetricsPath: PathFunction<SecretScanningMetricsParams> = params => {
    return `${this.rootPath()}/security/metrics/secret-scanning?${new URLSearchParams(params).toString()}`
  }

  secretsPushProtectionMetricsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/metrics/secret-scanning/push-protection-metrics?${new URLSearchParams(
      params,
    ).toString()}`
  }

  secretsPushProtectionBlocksByTokenTypeMetricsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/metrics/secret-scanning/push-protection-metrics/block-counts-by-token-type?${new URLSearchParams(
      params,
    ).toString()}`
  }

  secretsPushProtectionBlocksByRepositoryMetricsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/metrics/secret-scanning/push-protection-metrics/block-counts-by-repo?${new URLSearchParams(
      params,
    ).toString()}`
  }

  secretsPushProtectionBypassesByTokenTypeMetricsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/metrics/secret-scanning/push-protection-metrics/bypass-counts-by-token-type?${new URLSearchParams(
      params,
    ).toString()}`
  }

  secretsPushProtectionBypassesByRepositoryMetricsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/metrics/secret-scanning/push-protection-metrics/bypass-counts-by-repo?${new URLSearchParams(
      params,
    ).toString()}`
  }

  secretScanningAlertCentricViewPath: PathFunction<SecretScanningAlertCentricViewParams> = params => {
    return `${this.rootPath()}/security/alerts/secret-scanning?${new URLSearchParams(params).toString()}`
  }
  // #endregion

  onboardingAdvancedSecurityPath: PathFunction = () => {
    return orgOnboardingAdvancedSecurityPath({org: this.org})
  }
}

export class EnterprisePaths implements Paths {
  private declare biz: string
  constructor(biz: string) {
    this.biz = biz
  }

  private rootPath: PathFunction = () => `/enterprises/${encodePart(this.biz)}`

  // #region Options
  suggestionsPath: PathFunction<SuggestionsQueryParams> = props => {
    const {type} = props
    let path = `${this.rootPath()}/security/options?options-type=${type}`
    if (type === 'props') {
      path += `&name=${props.name}`
    }

    return path
  }
  // #endregion

  // #region Overview
  advisoriesPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/advisories?${new URLSearchParams(params).toString()}`
  }

  ageOfAlertsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/age-of-alerts?${new URLSearchParams(params).toString()}`
  }

  alertActivityPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/alert-activity?${new URLSearchParams(params).toString()}`
  }

  introducedAndPreventedPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/introduced-prevented?${new URLSearchParams(params).toString()}`
  }

  alertTrendsPath: PathFunction<AlertTrendsQueryParams> = ({alertState, grouping, query, ...rest}) => {
    const isOpenSelected = alertState !== 'closed'
    const params = new URLSearchParams({
      'alertTrendsChart[isOpenSelected]': isOpenSelected.toString(),
      query,
      ...rest,
    })

    let endpointSuffix: AlertTrendsEndpointSuffix = 'tool-code-scanning'
    switch (grouping) {
      case 'age':
        endpointSuffix = 'age'
        break
      case 'severity':
        endpointSuffix = 'severity'
        break
      case 'tool':
        if (query.includes('dependabot')) {
          endpointSuffix = 'tool-dependabot-alerts'
        } else if (query.includes('secret-scanning')) {
          endpointSuffix = 'tool-secret-scanning'
        }
        break
    }

    return `${this.rootPath()}/security/overview/alert-trends-by-${endpointSuffix}?${params.toString()}`
  }

  alertsFixedWithAutofixPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/alerts-fixed-with-autofix?${new URLSearchParams(params).toString()}`
  }

  historicalAlertsFixedWithAutofixPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/historical-alerts-fixed-with-autofix?${new URLSearchParams(
      params,
    ).toString()}`
  }

  csvExportPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/export?${new URLSearchParams(params).toString()}`
  }

  meanTimeToRemediatePath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/mean-time-to-remediate?${new URLSearchParams(params).toString()}`
  }

  netResolveRatePath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/net-resolve-rate?${new URLSearchParams(params).toString()}`
  }

  pullRequestAlertsFixedPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/pull-request-alerts-fixed?${new URLSearchParams(params).toString()}`
  }

  reopenedAlertsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/reopened-alerts?${new URLSearchParams(params).toString()}`
  }

  repositoriesPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/repositories?${new URLSearchParams(params).toString()}`
  }

  sastPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/sast?${new URLSearchParams(params).toString()}`
  }

  secretsBypassedPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/overview/secrets-bypassed?${new URLSearchParams(params).toString()}`
  }
  // #endregion

  // #region Enablement trends report
  enablementTrendsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/metrics/enablement/enablement-trends?${new URLSearchParams(params).toString()}`
  }
  // #endregion

  // #region Code Scanning report
  codeScanningMetricsPath: PathFunction<CodeScanningMetricsParams> = params =>
    `${this.rootPath()}/security/metrics/codeql?${toSearchParams(params).toString()}`

  codeScanningAlertsFoundPath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/alerts-found?${toSearchParams(params).toString()}`

  codeScanningAutofixSuggestionsPath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/autofix-suggestions?${toSearchParams(params).toString()}`

  codeScanningAlertsFixedPath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/alerts-fixed?${toSearchParams(params).toString()}`

  codeScanningAlertTrendsPath: PathFunction<CodeScanningReportParams & {groupKey: 'status' | 'severity'}> = ({
    groupKey,
    ...rest
  }) => {
    return `${this.rootPath()}/security/metrics/codeql/alert-trends-by-${groupKey}?${toSearchParams(rest)}`
  }

  codeScanningAlertsFixedWithAutofixPath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/alerts-fixed-with-autofix?${toSearchParams(params).toString()}`

  codeScanningRemediationRatesPath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/remediation-rates?${toSearchParams(params).toString()}`

  codeScanningRemediationTimePath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/remediation-time?${toSearchParams(params).toString()}`

  codeScanningMostPrevalentRulesPath: PathFunction<CodeScanningReportParams & PageParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/most-prevalent-rules?${toSearchParams(params).toString()}`

  codeScanningRepositoriesPath: PathFunction<CodeScanningReportParams & PageParams & SortParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/repositories?${toSearchParams(params).toString()}`

  codeScanningCsvExportPath: PathFunction<CodeScanningReportParams> = params =>
    `${this.rootPath()}/security/metrics/codeql/export?${toSearchParams(params).toString()}`
  // #endregion

  // #region Dependabot report
  dependabotMetricsPath: PathFunction<DependabotMetricsParams> = () => {
    throw new Error('dependabotMetricsPath not available for enterprise')
  }

  dependabotAlertsFixedPath: PathFunction<DependabotMetricsParams> = () => {
    throw new Error('dependabotAlertsFixedPath not available for enterprise')
  }

  dependabotAlertTrendsPath: PathFunction<DependabotMetricsParams> = () => {
    throw new Error('dependabotAlertTrendsPath not available for enterprise')
  }

  dependabotAlertsListPath: PathFunction<{query: string}> = ({query}) =>
    `${this.rootPath()}/security/alerts/dependabot?q=${encodeURIComponent(query)}`

  dependabotRepositoriesPath: PathFunction<DependabotMetricsParams & PageParams & SortParams> = () => {
    throw new Error('dependabotRepositoriesPath not available for enterprise')
  }
  // #endregion

  // #region Secret Scanning report
  secretScanningMetricsPath: PathFunction<SecretScanningMetricsParams> = params => {
    return `${this.rootPath()}/security/metrics/secret-scanning?${new URLSearchParams(params).toString()}`
  }

  secretsPushProtectionMetricsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/metrics/secret-scanning/push-protection-metrics?${new URLSearchParams(
      params,
    ).toString()}`
  }

  secretsPushProtectionBlocksByTokenTypeMetricsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/metrics/secret-scanning/push-protection-metrics/block-counts-by-token-type?${new URLSearchParams(
      params,
    ).toString()}`
  }

  secretsPushProtectionBlocksByRepositoryMetricsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/metrics/secret-scanning/push-protection-metrics/block-counts-by-repo?${new URLSearchParams(
      params,
    ).toString()}`
  }

  secretsPushProtectionBypassesByTokenTypeMetricsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/metrics/secret-scanning/push-protection-metrics/bypass-counts-by-token-type?${new URLSearchParams(
      params,
    ).toString()}`
  }

  secretsPushProtectionBypassesByRepositoryMetricsPath: PathFunction<CardQueryParams> = params => {
    return `${this.rootPath()}/security/metrics/secret-scanning/push-protection-metrics/bypass-counts-by-repo?${new URLSearchParams(
      params,
    ).toString()}`
  }

  secretScanningAlertCentricViewPath: PathFunction<SecretScanningAlertCentricViewParams> = params => {
    return `${this.rootPath()}/security/alerts/secret-scanning?${new URLSearchParams(params).toString()}`
  }

  // #endregion

  onboardingAdvancedSecurityPath: PathFunction = () => {
    throw new Error('onboardingAdvancedSecurityPath not available for enterprise')
  }
}
