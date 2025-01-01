import {Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {InfoIcon} from '@primer/octicons-react'
import {PUSH_RULESET_TARGET_INFO} from '../../helpers/constants'

export const PushRulePublicTargetingBanner = () => {
  return (
    <Flash>
      <div className="d-flex flex-row flex-items-center">
        <Octicon icon={InfoIcon} />
        <span>{PUSH_RULESET_TARGET_INFO}</span>
      </div>
    </Flash>
  )
}
