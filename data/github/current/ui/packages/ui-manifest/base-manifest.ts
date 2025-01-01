import {bundlerFlags} from './bundler-flags.ts'
import {getCurrentGitSha} from './git-sha.ts'
import {getClientFeatureFlags} from './feature-flags.ts'
import type {UIManifestBase} from './manifest-types.ts'

export async function getBaseManifest(): Promise<UIManifestBase> {
  const gitShaPromise = getCurrentGitSha()
  return {
    gitSha: await gitShaPromise,
    bundlerFlags,
    featureFlags: getClientFeatureFlags(),
  }
}
