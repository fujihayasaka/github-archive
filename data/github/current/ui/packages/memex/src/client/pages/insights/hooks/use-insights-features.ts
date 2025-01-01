import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import {useProjectState} from '../../../state-providers/memex/use-project-state'

/**
 * A hook for dealing with insights specific flag logic
 */
export function useInsightsEnabledFeatures() {
  const {isPublicProject} = useProjectState()
  const {memex_insights_basic_private, memex_insights_basic_public} = useEnabledFeatures()

  // Typically granted to Enterprise Cloud plans (aka business_plus).
  const isInsightsEligible = isPublicProject ? memex_insights_basic_public : memex_insights_basic_private

  return {
    /*
     * Whether Insights platform historical charts are considered a fully supported feature based on the memex owner's plan,
     * regardless of if Insights are enabled.
     */
    isInsightsEligible,
  }
}
