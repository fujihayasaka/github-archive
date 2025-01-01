import {useState, type MouseEvent} from 'react'
import {Box, Checkbox, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {ControlGroup} from '@github-ui/control-group'
import {ShieldLockIcon} from '@primer/octicons-react'

interface Props {
  canCollectPrivateTelemetry: boolean
  defaultValue: boolean
  org: string
  policyPath: string
}

export function PrivateTelemetryCheckbox({canCollectPrivateTelemetry, defaultValue, org, policyPath}: Props) {
  const [collectPrivateTelemetry, setCollectPrivateTelemetry] = useState(defaultValue)

  const handleClick = (e: MouseEvent<HTMLButtonElement>) => {
    e.preventDefault()
    setCollectPrivateTelemetry(!collectPrivateTelemetry)
  }

  return (
    <Box sx={{borderTop: '1px solid var(--borderColor-default)', p: '4px'}}>
      <ControlGroup border={false}>
        <ControlGroup.Item>
          <ControlGroup.Title id="private_telemetry">Include data from developer telemetry</ControlGroup.Title>
          <ControlGroup.Description>
            Train the model on data collected from developer&apos;s prompts and suggestions for fine-tuning your model.
            It is strongly recommended to include this data to improve model performance.
            {!canCollectPrivateTelemetry && (
              <Box sx={{alignItems: 'center', display: 'flex', gap: '5px', mt: '2px'}}>
                <Octicon icon={ShieldLockIcon} size={16} />
                Managed by{' '}
                <Link href={policyPath} inline>
                  {org}
                </Link>
              </Box>
            )}
          </ControlGroup.Description>
          {canCollectPrivateTelemetry ? (
            <ControlGroup.ToggleSwitch
              aria-labelledby="private_telemetry"
              checked={collectPrivateTelemetry}
              onClick={handleClick}
            />
          ) : (
            <ControlGroup.Custom>Disabled</ControlGroup.Custom>
          )}
        </ControlGroup.Item>
      </ControlGroup>

      <Checkbox
        checked={collectPrivateTelemetry}
        name="private_telemetry"
        readOnly
        sx={{display: 'none'}}
        value={canCollectPrivateTelemetry ? 'on' : 'off'}
      />
    </Box>
  )
}
