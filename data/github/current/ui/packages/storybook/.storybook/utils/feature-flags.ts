import {mockClientEnv} from '@github-ui/client-env/mock'
import type {JSFeatureFlag} from '@github-ui/feature-flags/client-feature-flags'

const FEATURE_FLAG_SEPARATOR = '--'

export function buildFeatureFlagsValue(featureFlags: Set<JSFeatureFlag> | JSFeatureFlag[]) {
  return Array.from(featureFlags).join(FEATURE_FLAG_SEPARATOR)
}

const defaultFeatureFlags: JSFeatureFlag[] = ['primer_react_css_modules_ga']
export const defaultFeatureFlagsValue = buildFeatureFlagsValue(defaultFeatureFlags)

export function extractFeatureFlags(globals: Record<string, any>) {
  const featureFlagsValue: string = globals.featureFlags ?? ''
  return featureFlagsValue
    .split(FEATURE_FLAG_SEPARATOR)
    .map(flag => flag.trim())
    .filter(Boolean) as JSFeatureFlag[]
}

// Start with the default feature flags enabled
mockClientEnv({
  featureFlags: defaultFeatureFlags,
})
