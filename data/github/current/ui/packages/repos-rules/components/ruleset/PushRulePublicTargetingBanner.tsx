import {Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {InfoIcon} from '@primer/octicons-react'

export const PushRulePublicTargetingBanner = () => {
  return (
    <Flash>
      <div className="d-flex flex-row flex-items-center">
        <Octicon icon={InfoIcon} />
        <span>Push rulesets only apply to private or internal repositories and their forks.</span>
      </div>
    </Flash>
  )
}
