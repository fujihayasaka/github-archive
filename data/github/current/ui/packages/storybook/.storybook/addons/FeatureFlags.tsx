import React from 'react'
import {jsFeatureFlags, type JSFeatureFlag} from '@github-ui/feature-flags/client-feature-flags'
import {IconButton, TooltipLinkList, WithTooltip} from '@storybook/components'
import {BeakerIcon} from '@storybook/icons'
import {useGlobals} from '@storybook/manager-api'
import {buildFeatureFlagsValue, extractFeatureFlags} from '../utils/feature-flags'

export const FEATURE_FLAGS_ADDON_ID = 'feature-flags'
export const FEATURE_FLAGS_TOOL_ID = `${FEATURE_FLAGS_ADDON_ID}/tool`

export function FeatureFlags() {
  const [globals, updateGlobals] = useGlobals()
  const featureFlagsSet = new Set(extractFeatureFlags(globals))
  return (
    <WithTooltip
      placement="top"
      trigger="click"
      closeOnOutsideClick
      tooltip={({onHide}) => {
        return (
          <TooltipLinkList
            links={jsFeatureFlags
              .map(featureFlag => {
                const active = featureFlagsSet.has(featureFlag)
                return {
                  id: featureFlag,
                  title: active ? `✅ ${featureFlag}` : featureFlag,
                  active,
                  onClick: () => {
                    const enabled = !featureFlagsSet.has(featureFlag)
                    if (enabled) {
                      featureFlagsSet.add(featureFlag)
                    } else {
                      featureFlagsSet.delete(featureFlag)
                    }
                    updateGlobals({
                      featureFlags: buildFeatureFlagsValue(featureFlagsSet),
                    })
                    onHide()
                  },
                }
              })
              .sort((a, b) => {
                // Sort active flags to the top
                if (a.active && !b.active) {
                  return -1
                }
                if (!a.active && b.active) {
                  return 1
                }
                return 0
              })}
          />
        )
      }}
    >
      <IconButton active={featureFlagsSet.size > 0} title="Toggle feature flags" style={{position: 'relative'}}>
        <BeakerIcon size={14} />
      </IconButton>
    </WithTooltip>
  )
}
