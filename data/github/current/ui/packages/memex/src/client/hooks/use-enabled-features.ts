import type {EnabledFeaturesMap} from '@github-ui/memex-feature-flags'

import {getEnabledFeatures} from '../helpers/feature-flags'

// eslint-disable-next-line @eslint-react/hooks-extra/no-unnecessary-use-prefix
export const useEnabledFeatures = (): EnabledFeaturesMap => {
  return getEnabledFeatures()
}
