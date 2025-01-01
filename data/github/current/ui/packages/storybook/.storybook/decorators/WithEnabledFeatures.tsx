import {mockClientEnv} from '@github-ui/client-env/mock'
import {PrimerFeatureFlags} from '@github-ui/react-core/PrimerFeatureFlags'
import type {Decorator} from '@storybook/react'
import {extractFeatureFlags} from '../utils/feature-flags'

export const withEnabledFeatures: Decorator = (Story, context) => {
  const globalFlags = extractFeatureFlags(context.globals)
  const featureFlags = new Set(globalFlags)
  const {parameters} = context
  if (parameters.enabledFeatures && Array.isArray(parameters.enabledFeatures)) {
    for (const feature of parameters.enabledFeatures) {
      featureFlags.add(feature)
    }
  }

  mockClientEnv({locale: 'en', featureFlags: Array.from(featureFlags)})
  return (
    <PrimerFeatureFlags>
      {Story(context)}
    </PrimerFeatureFlags>
  )
}
