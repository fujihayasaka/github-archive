import type {EnabledFeaturesMap} from '../api/enabled-features/contracts'
import {getEnabledFeatures} from '../helpers/feature-flags'

// eslint-disable-next-line @eslint-react/hooks-extra/no-redundant-custom-hook
export const useEnabledFeatures = (): EnabledFeaturesMap => {
  return getEnabledFeatures()
}
