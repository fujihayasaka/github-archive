// @ts-check
import eslintBuildConfig from '@github-ui/eslintrc/build'
import ensureLocalWorkspaceExistsRule from './lint/ensure-local-workspace-exists.mjs'
import {getWorkspacePackages} from './lint/get-workspaces-packages.mjs'

export default [
  ...eslintBuildConfig,
  {
    files: ['**/managed-dependencies.js'],
    plugins: {
      'managed-dependencies-local-rule': {
        rules: {
          'ensure-local-workspace-exists': ensureLocalWorkspaceExistsRule(getWorkspacePackages),
        },
      },
    },
    rules: {
      'managed-dependencies-local-rule/ensure-local-workspace-exists': 'error',
    },
  },
]
