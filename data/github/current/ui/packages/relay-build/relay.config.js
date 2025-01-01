// @ts-check
const {rootPath, PERSISTED_QUERIES_FILE_PATH} = require('./config-paths')
const {getRepoAgnosticPath} = require('@github-ui/client-build-tools/path-utils')

/**
 * @type {{
 *   root: string
 *   src: string
 *   sources: Record<string, string>
 *   excludes: string[]
 *   projects: Record<string, {
 *     schema: string
 *     schemaExtensions: string[]
 *     customScalarTypes: Record<string, string>
 *     persist: {
 *       file: string[]
 *     }
 *   }>
 * }}
 */
module.exports = {
  /** The path root from which sources are evaluated  */
  root: rootPath,
  /** A Map of source path to project name, ie 'app/assets/modules/pulls-dashboard': 'github-ui */
  sources: Object.fromEntries(
    [
      'app/assets/modules/pulls-dashboard',
      'app/assets/modules/react-shared/Notifications',
      'app/assets/modules/repo-deployments',
      'ui/packages/billing-app',
      'ui/packages/commenting',
      'ui/packages/contributor-footer',
      'ui/packages/commits',
      'ui/packages/copilot-code-chat',
      'ui/packages/copilot-immersive-v1',
      'ui/packages/copilot-plan-brainstorm',
      'ui/packages/issue-actions',
      'ui/packages/issue-body',
      'ui/packages/issue-create',
      'ui/packages/issue-form',
      'ui/packages/issue-metadata',
      'ui/packages/issue-types',
      'ui/packages/issue-type-filter-provider',
      'ui/packages/issue-viewer',
      'ui/packages/issues-react',
      'ui/packages/item-picker',
      'ui/packages/list-view-items-issues-prs',
      'ui/packages/markdown-edit-history-viewer',
      'ui/packages/memex',
      'ui/packages/mergebox',
      'ui/packages/navigation-test',
      'ui/packages/notifications-inbox',
      'ui/packages/query-builder/providers',
      'ui/packages/react-sandbox',
      'ui/packages/reaction-viewer',
      'ui/packages/relay-test-utils',
      'ui/packages/repository-milestone',
      'ui/packages/repository-label',
      'ui/packages/issues-bulk-actions',
      'ui/packages/sub-issues',
      'ui/packages/timeline-items',
      'ui/packages/workspace-editor',
      'ui/packages/global-create-menu',
    ].map(source => {
      return [getRepoAgnosticPath(source), 'github-ui']
    }),
  ),
  /** A list of patterns to exclude from compilation. Usually generated / already compiled graphql files */
  excludes: ['**/__generated__/**'],
  /** A map of projects (like github-ui) to their project level config */
  projects: {
    'github-ui': {
      /** the graphql schema to utilize */
      schema: 'config/schema.internal.graphql',
      /** a list of paths to schema extensions */
      schemaExtensions: ['ui/packages/relay-environment/graphql', 'ui/packages/issues-react/graphql'].map(
        getRepoAgnosticPath,
      ),
      /** the language parser for evaluating sources */
      language: 'typescript',
      /** Additional custom types evaluated as scalars */
      customScalarTypes: {
        URI: 'string',
        HTML: 'string',
        DateTime: 'string',
      },
      /** a config for persisted query generation */
      persist: {
        /** the file where the persisted query map is written */
        file: PERSISTED_QUERIES_FILE_PATH,
      },
      /** ensure generated code can be run in esm environments */
      eagerEsModules: true,
      /** use type imports whenever possible, ensuring esm compatibility */
      useImportTypeSyntax: true,
    },
  },
}
