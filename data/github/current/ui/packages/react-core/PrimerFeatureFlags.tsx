import {getEnabledFeatures} from '@github-ui/feature-flags'
import {FeatureFlags} from '@primer/react/experimental'
import React from 'react'

interface PrimerFeatureFlagsProps extends React.PropsWithChildren {}

export function PrimerFeatureFlags({children}: PrimerFeatureFlagsProps) {
  const flags = React.useMemo(() => {
    const featureFlags = getEnabledFeatures()
    const result: Record<string, boolean> = {}
    for (const flag of featureFlags) {
      if (flag.startsWith('primer_react_')) {
        result[flag] = true
      }
    }
    return result
  }, [])

  return <FeatureFlags flags={flags}>{children}</FeatureFlags>
}
