import {rgPath} from '@vscode/ripgrep'
import {exec} from 'node:child_process'
import {promisify} from 'node:util'
import type {UIManifest} from './manifest-types'
import {jsFeatureFlags, cssFeatureFlags} from '@github-ui/feature-flags/client-feature-flags'
import {clientFeatureFlags, projectActorFeatureFlags, featurePreviews} from '@github-ui/memex-feature-flags'
import {getAssetsBasePath} from './paths.ts'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'

export function getClientFeatureFlags(): FeatureFlags {
  return {
    js: jsFeatureFlags,
    css: cssFeatureFlags,
    memex: {
      client: clientFeatureFlags,
      projectActor: projectActorFeatureFlags,
      previews: featurePreviews,
    },
  }
}

const execAsync = promisify(exec)
type FeatureFlags = UIManifest['featureFlags']

async function findFlagsInFiles(flagName: string, flagMatcher: string, fileMatcher: string): Promise<boolean> {
  try {
    await execAsync(`${rgPath} ${flagMatcher} ${fileMatcher} --quiet`, {
      cwd: fullPathFromRoot(getAssetsBasePath()),
    })

    return true
  } catch {
    console.error(
      `❌ The flag "${flagName}" was not found in any ${fileMatcher} output files. Please remove this flag from ui/packages/feature-flags/client-feature-flags.ts`,
    )
    return false
  }
}

export async function validateClientFeatureFlags() {
  console.log('Validating client feature flags...')
  const jsFlagMatchPromises = jsFeatureFlags.map(flag => findFlagsInFiles(flag, `${flag}`, '*.js'))
  const cssFlagMatchPromises = cssFeatureFlags.map(flag =>
    findFlagsInFiles(flag, `data-css-features~="${flag}"`, '*.css'),
  )

  const results = await Promise.all([...jsFlagMatchPromises, ...cssFlagMatchPromises])

  if (results.some(result => !result)) {
    throw new Error('Feature flags validation failed. Please check the logs above for more details.')
  }
  console.timeEnd('validateClientFeatureFlags')
  console.log(`✅ Found matches for ${results.length} client feature flags`)
}
