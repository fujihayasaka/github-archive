import {App} from './App'
import {OverviewPage} from './routes/OverviewPage'
import {RulesetPage} from './routes/RulesetPage'
import {InsightsPage} from './routes/InsightsPage'
import {HistoryComparisonPage} from './routes/HistoryComparisonPage'
import {HistorySummaryPage} from './routes/HistorySummaryPage'
import {registerReactAppFactory} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

const STANDARD_ROUTES = [
  jsonRoute({path: '/:owner/:repo/settings/rules', Component: OverviewPage}),
  jsonRoute({path: '/:owner/:repo/settings/rules/insights', Component: InsightsPage}),
  jsonRoute({path: '/:owner/:repo/settings/rules/:rulesetId', Component: RulesetPage}),
  jsonRoute({
    path: '/:owner/:repo/settings/rules/:rulesetId/history/:historyId/compare/*',
    Component: HistoryComparisonPage,
  }),
  jsonRoute({path: '/:owner/:repo/settings/rules/:rulesetId/history', Component: HistorySummaryPage}),
  /* Read only pages */
  jsonRoute({path: '/:owner/:repo/settings/rules/:rulesetId/history/:historyId/view', Component: RulesetPage}),
  jsonRoute({path: '/:owner/:repo/rules', Component: OverviewPage}),
  jsonRoute({path: '/:owner/:repo/rules/:rulesetId', Component: RulesetPage}),
  jsonRoute({path: '/:owner/:repo/rules/:rulesetId/history', Component: HistorySummaryPage}),
]

const STAFFTOOLS_ROUTES = [
  /* Stafftools */
  jsonRoute({path: '/stafftools/repositories/:owner/:repo/repository_rules', Component: OverviewPage}),
  jsonRoute({path: '/stafftools/repositories/:owner/:repo/repository_rules/insights', Component: InsightsPage}),
  jsonRoute({path: '/stafftools/repositories/:owner/:repo/repository_rules/:rulesetId', Component: RulesetPage}),
  jsonRoute({
    path: '/stafftools/repositories/:owner/:repo/repository_rules/:rulesetId/history/:historyId/compare/*',
    Component: HistoryComparisonPage,
  }),
  jsonRoute({
    path: '/stafftools/repositories/:owner/:repo/repository_rules/:rulesetId/history',
    Component: HistorySummaryPage,
  }),
  jsonRoute({path: '/stafftools/users/:organizationId/organization_rules', Component: OverviewPage}),
  jsonRoute({path: '/stafftools/users/:organizationId/organization_rules/insights', Component: InsightsPage}),
  jsonRoute({path: '/stafftools/users/:organizationId/organization_rules/:rulesetId', Component: RulesetPage}),
  jsonRoute({
    path: '/stafftools/users/:organizationId/organization_rules/:rulesetId/history/:historyId/compare/*',
    Component: HistoryComparisonPage,
  }),
  jsonRoute({
    path: '/stafftools/users/:organizationId/organization_rules/:rulesetId/history',
    Component: HistorySummaryPage,
  }),
]

const ORG_MEMBER_PRIVILEGE_ROUTES = [
  jsonRoute({path: '/organizations/:org/settings/policies/:policy_type', Component: OverviewPage}),
  jsonRoute({path: '/organizations/:org/settings/policies/:policy_type/:rulesetId', Component: RulesetPage}),
  jsonRoute({
    path: '/organizations/:org/settings/policies/:policy_type/:rulesetId/history',
    Component: HistorySummaryPage,
  }),
  jsonRoute({
    path: '/organizations/:org/settings/policies/:policy_type/:rulesetId/history/:historyId/compare/*',
    Component: HistoryComparisonPage,
  }),
]

const ENTERPRISE_POLICY_ROUTES = [
  jsonRoute({path: '/enterprises/:enterprise/settings/policies/:policy_type', Component: OverviewPage}),
  jsonRoute({path: '/enterprises/:enterprise/settings/policies/:policy_type/insights', Component: InsightsPage}),
  jsonRoute({path: '/enterprises/:enterprise/settings/policies/:policy_type/:rulesetId', Component: RulesetPage}),
  jsonRoute({
    path: '/enterprises/:enterprise/settings/policies/:policy_type/:rulesetId/history',
    Component: HistorySummaryPage,
  }),
  jsonRoute({
    path: '/enterprises/:enterprise/settings/policies/:policy_type/:rulesetId/history/:historyId/compare/*',
    Component: HistoryComparisonPage,
  }),
  jsonRoute({
    path: '/enterprises/:enterprise/settings/policies/:policy_type/:rulesetId/history/:historyId/view',
    Component: RulesetPage,
  }),
]

registerReactAppFactory('repos-rules', () => ({
  App,
  routes: [...STANDARD_ROUTES, ...STAFFTOOLS_ROUTES, ...ORG_MEMBER_PRIVILEGE_ROUTES, ...ENTERPRISE_POLICY_ROUTES],
}))
