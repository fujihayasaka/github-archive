import memoize from '@github/memoize'
import {getEnv} from '@github-ui/client-env'
import {IS_SERVER} from '@github-ui/ssr-utils'
import type {JSFeatureFlag} from './client-feature-flags'

function getEnabledFeaturesSet() {
  return new Set(getEnv().featureFlags as JSFeatureFlag[])
}

const featuresSet =
  IS_SERVER || process.env.NODE_ENV === 'test' || isStorybook() ? getEnabledFeaturesSet : memoize(getEnabledFeaturesSet)

export function getEnabledFeatures(): JSFeatureFlag[] {
  return Array.from(featuresSet())
}

/**
 * This function accesses feature flag states which have been loaded into the client env via the `client-feature-flags.ts` file.
 * See https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/overview/#feature-flags-in-the-typescript-front-end
 * for more details.
 *
 * If you're trying to check a feature flag that was added to the `enabled_features` of a React payload via `add_client_feature_flag` in a
 * Rails controller, you should use the `useFeatureFlag` hook (from `@github-ui/react-core/use-feature-flag`) instead to access the feature flag state.
 * https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/overview/#feature-flags-in-the-typescript-front-end has
 * more information on `useFeatureFlag` and `add_client_feature_flag`.
 */
export function isFeatureEnabled(name: JSFeatureFlag): boolean {
  return featuresSet().has(name)
}

// exported to allow mocking in tests
const featureFlag = {isFeatureEnabled}

export {featureFlag}

function isStorybook() {
  try {
    return process?.env?.STORYBOOK === 'true' || process?.env?.APP_ENV === 'storybook'
  } catch {
    return false
  }
}
