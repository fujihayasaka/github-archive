import type {EnabledFeaturesMap} from '../api/enabled-features/contracts'
import {getEnabledFeatures} from '../helpers/feature-flags'

// eslint-disable-next-line @eslint-react/hooks-extra/no-useless-custom-hooks
export const useEnabledFeatures = (): EnabledFeaturesMap => {
  return getEnabledFeatures()
}
