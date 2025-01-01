import {FormControl, Radio, RadioGroup} from '@primer/react'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {useState} from 'react'

export interface ActionsCustomImagesPolicyProps {
  accessPolicy: AccessPolicy
  action: string
}

export interface IActionsCustomImagesPolicyUpdate {
  accessPolicy: AccessPolicy
}

// See lib/configurable/actions_custom_images_policy.rb
type AccessPolicy = 'all' | 'selected' | 'none'

export function ActionsCustomImagesPolicy(props: ActionsCustomImagesPolicyProps) {
  const [accessPolicy, setAccessPolicy] = useState<AccessPolicy>(props.accessPolicy)
  const [error, setError] = useState(false)

  return (
    <div>
      <p id="customImagesInOrgsLabel">
        Choose which organizations are allowed to create custom images to be assigned to runners.
      </p>
      <RadioGroup
        name="customImagesInOrgs"
        aria-labelledby="customImagesInOrgsLabel"
        onChange={e => updateAccessPolicy(e as AccessPolicy)}
      >
        <FormControl>
          <Radio value="all" checked={accessPolicy === 'all'} />
          <FormControl.Label>Enable for all organizations</FormControl.Label>
          <FormControl.Caption>
            All organizations, including any created in the future, may use or create custom images.
          </FormControl.Caption>
        </FormControl>
        <FormControl>
          <Radio value="selected" checked={accessPolicy === 'selected'} />
          <FormControl.Label>Enable for specific organizations</FormControl.Label>
          <FormControl.Caption>
            Only specifically-selected organizations may use or create custom images.
          </FormControl.Caption>
        </FormControl>
        <FormControl>
          <Radio value="none" checked={accessPolicy === 'none'} />
          <FormControl.Label>Disabled for all organizations</FormControl.Label>
          <FormControl.Caption>No organization may use or create custom images.</FormControl.Caption>
        </FormControl>
        {error && (
          <RadioGroup.Validation variant="error">
            Failed to update the custom images policy, please try again later.
          </RadioGroup.Validation>
        )}
      </RadioGroup>
    </div>
  )

  async function updateAccessPolicy(e: AccessPolicy) {
    setAccessPolicy(e)
    const update: IActionsCustomImagesPolicyUpdate = {accessPolicy: e}
    const response = await reactFetchJSON(props.action, {method: 'PUT', body: update})
    if (response.ok) {
      setError(false)
      window.location.reload()
    } else {
      setError(true)
    }
  }
}
