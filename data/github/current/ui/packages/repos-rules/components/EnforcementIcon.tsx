import {Box, Text} from '@primer/react'
import {Octicon, Tooltip} from '@primer/react/deprecated'
import {MeterIcon, SkipIcon, PlayIcon, NoEntryIcon} from '@primer/octicons-react'
import type {UpsellInfo} from '../types/rules-types'
import {RulesetEnforcement} from '../types/rules-types'
import {enforcementLabelText} from '../helpers/enforcement-label'

export function EnforcementIcon({
  upsellInfo,
  hideText,
  enforcement,
}: {
  upsellInfo?: UpsellInfo
  hideText?: boolean
  enforcement: RulesetEnforcement
}) {
  let text = ''
  let icon: JSX.Element | null = null

  if (
    upsellInfo &&
    ((!upsellInfo.rulesets.featureEnabled && enforcement !== RulesetEnforcement.Disabled) ||
      (!upsellInfo.enterpriseRulesets.featureEnabled && enforcement === RulesetEnforcement.Evaluate))
  ) {
    text = 'Not enforced'
    icon = <Octicon icon={NoEntryIcon} sx={{marginRight: 1, color: 'attention.fg'}} aria-label="Not enforced" />
  } else {
    text = enforcementLabelText(enforcement)
    switch (enforcement) {
      case RulesetEnforcement.Enabled:
        icon = <Octicon icon={PlayIcon} sx={{marginRight: 1, color: 'success.fg'}} aria-label={text} />
        break
      case RulesetEnforcement.Evaluate:
        icon = <Octicon icon={MeterIcon} sx={{marginRight: 1, color: 'severe.fg'}} aria-label={text} />
        break
      default:
        icon = <Octicon icon={SkipIcon} sx={{marginRight: 1, color: 'fg.muted'}} aria-label={text} />
        break
    }
  }

  return hideText ? (
    <Tooltip text={text}>{icon}</Tooltip>
  ) : (
    <Box
      as="span"
      sx={{
        alignItems: 'center',
        display: 'inline-flex',
        backgroundColor: 'neutral.subtle',
        borderRadius: 2,
        paddingLeft: 1,
        paddingRight: 2,
        paddingY: 1,
      }}
    >
      {icon}
      <Text sx={{fontSize: 0, fontWeight: 'bold'}}>{text}</Text>
    </Box>
  )
}
