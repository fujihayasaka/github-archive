import {Link} from '@primer/react'
import type {CopilotForBusinessGeneralPolicy, CopilotForBusinessPoliciesPayload} from '../types'
import {ShieldLockIcon} from '@primer/octicons-react'
import {ActionMenuButton} from '../traditional/components/ActionMenuButton'
import PreviewFeatureHeading from './PreviewFeatureHeading'
import {useUIAspectFromRoute} from '../hooks/use-ui-aspect-from-route'
import {useOptions} from '../hooks/use-options'

export default function GeneralPolicy({policyName}: {policyName: keyof CopilotForBusinessPoliciesPayload}) {
  const data = useUIAspectFromRoute(policyName) as CopilotForBusinessGeneralPolicy
  const {onSelect, options, selected, loading} = useOptions({
    items: data.options,
    controls: data.manages,
    defaultOption: {
      value: 'NA',
      id: 'unconfigured',
      title: 'Unconfigured',
    },
  })

  const disabled = !data.configurable

  if (!data.visible) {
    return null
  }

  return (
    <>
      <div data-testid={`cfb-policies-${policyName}-feature`} style={{maxWidth: 750}}>
        <PreviewFeatureHeading title={data.displayname} beta={data.preview} />
        {data.description}
        <br />
        {data.helpurl && (
          <Link href={data.helpurl} inline>
            {data.helptext}
          </Link>
        )}
      </div>
      {disabled ? (
        <span data-testid={`cfb-policies-${policyName}-feature-locked`}>
          <ShieldLockIcon /> {selected?.title ?? 'Disabled'}
        </span>
      ) : (
        <ActionMenuButton
          title={selected?.title ?? 'Disabled'}
          options={options}
          onSelect={onSelect}
          disabled={disabled}
          loading={loading}
          data-testid={`cfb-policies-${policyName}-control`}
        />
      )}
    </>
  )
}
