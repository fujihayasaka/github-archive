import {useState} from 'react'
import {testIdProps} from '@github-ui/test-id-props'
import {FormControl, Radio, Select, TextInput} from '@primer/react'

import styles from './FiscalHostPayout.module.css'

export interface FiscalHostPayoutProps {
  fiscalHostPayout: boolean
  fiscalHosts: FiscalHosts
}

export interface FiscalHosts {
  [sponsorable_login: string]: {
    name: string
    sponsorsListingId: number
  }
}

export function FiscalHostPayout({fiscalHostPayout, fiscalHosts}: FiscalHostPayoutProps) {
  const [fiscalHostLogin, setFiscalHostLogin] = useState('')

  return (
    <>
      <div className={styles.Box}>
        <FormControl>
          <Radio value="host" aria-describedby="host-description" />
          <FormControl.Label className={styles.FormControl_Label}>Fiscal Host</FormControl.Label>
        </FormControl>
        <span id="host-description" className="note">
          Members of supported fiscal hosts can use their fiscal host to join GitHub Sponsors instead of using a bank
          account.
        </span>
      </div>
      {fiscalHostPayout && (
        <FormControl className={styles.Box}>
          <FormControl.Label>Choose a fiscal host</FormControl.Label>
          <Select
            name="sponsors_listing[parent_listing_id]"
            onChange={event => {
              setFiscalHostLogin(event.target.value)
            }}
            className={styles.Select}
            {...testIdProps('residence-country')}
          >
            <Select.Option value="">Select a fiscal host</Select.Option>
            {Object.entries(fiscalHosts).map(([key, fiscalHost]) => (
              <Select.Option key={key} value={fiscalHost.sponsorsListingId.toString() || ''}>
                {fiscalHost.name}
              </Select.Option>
            ))}
          </Select>
        </FormControl>
      )}
      {fiscalHostPayout && fiscalHostLogin !== '' && (
        <FormControl className={styles.Box}>
          <FormControl.Label>Fiscal host project profile URL</FormControl.Label>
          <TextInput
            name="sponsors_listing[fiscally_hosted_project_profile_url]"
            block
            aria-describedby="fiscal-profile-url-description"
          />
          <span className="note" id="fiscal-profile-url-description">
            Please include a link to your profile on your fiscal host’s site, if available. <br />
            e.g., <code>https://opencollective.com/babel</code>
          </span>
        </FormControl>
      )}
    </>
  )
}
