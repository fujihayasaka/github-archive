import {Box, Button, FormControl, Radio, RadioGroup, Text} from '@primer/react'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {useState} from 'react'
import {OrgSelectionDialog} from './OrgSelectionDialog'
import {AccessPolicy} from './types'
import type {SimpleOrganization} from './types'

export interface ActionsCustomImagesPolicyProps {
  accessPolicy: AccessPolicy
  action: string
  bulkOrgAction: string
  orgs: SimpleOrganization[]
}

interface IActionsCustomImagesPolicyUpdate {
  accessPolicy: AccessPolicy
}

export function ActionsCustomImagesPolicy(props: ActionsCustomImagesPolicyProps) {
  const [accessPolicy, setAccessPolicy] = useState<AccessPolicy>(props.accessPolicy)
  const [error, setError] = useState(false)
  const [showDialog, setShowDialog] = useState(false)
  const [selectedOrgs, _] = useState<SimpleOrganization[]>(props.orgs.filter(org => org.selected))

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
          <FormControl.Label>Enable for all organizations</FormControl.Label>
          <FormControl.Caption>
            All organizations, including any created in the future, may use or create custom images.
          </FormControl.Caption>
          <Radio value={AccessPolicy.All} checked={accessPolicy === AccessPolicy.All} />
        </FormControl>
        <FormControl>
          <FormControl.Label>Enable for specific organizations</FormControl.Label>
          <FormControl.Caption>
            Only specifically-selected organizations may use or create custom images.
          </FormControl.Caption>
          <Radio value={AccessPolicy.Selected} checked={accessPolicy === AccessPolicy.Selected} />
        </FormControl>
        {props.accessPolicy === AccessPolicy.Selected && (
          <Box sx={{maxWidth: 300, paddingLeft: 4}}>
            <Button onClick={() => setShowDialog(true)} data-testid="select-orgs-button">
              <Text sx={{color: 'fg.muted'}}>Organizations:</Text>
              <Text sx={{color: 'fg.default', marginLeft: 2}}>{selectedOrgs.length} selected</Text>
            </Button>
          </Box>
        )}
        <FormControl>
          <FormControl.Label>Disabled for all organizations</FormControl.Label>
          <FormControl.Caption>No organization may use or create custom images.</FormControl.Caption>
          <Radio value={AccessPolicy.None} checked={accessPolicy === AccessPolicy.None} />
        </FormControl>
        {error && (
          <RadioGroup.Validation variant="error">
            Failed to update the custom images policy, please try again later.
          </RadioGroup.Validation>
        )}
      </RadioGroup>
      {showDialog && (
        <OrgSelectionDialog
          organizations={props.orgs}
          action={props.bulkOrgAction}
          closeDialog={() => setShowDialog(false)}
        />
      )}
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
