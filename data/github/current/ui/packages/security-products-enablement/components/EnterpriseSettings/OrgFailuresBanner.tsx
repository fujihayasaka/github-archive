import {Banner} from '@primer/react/experimental'
import type {EnterpriseOrgFailures} from '../../security-products-enablement-types'
import pluralize from 'pluralize'
import {Link as PrimerLink} from '@primer/react'
import {settingsOrgSecurityProductsPath} from '@github-ui/paths'
import {useState} from 'react'
import {OrgFailuresDialog} from './OrgFailuresDialog'

import styles from './OrgFailuresBanner.module.css'

export interface OrgFailuresBannerProps {
  failures: EnterpriseOrgFailures
}

const OrgFailuresBanner: React.FC<OrgFailuresBannerProps> = ({failures}) => {
  const [showFailedOrgDialog, setShowFailedOrgDialog] = useState(false)
  if (!failures || !failures.orgs || failures.totalRepoFailures === 0) return null

  const numberOfFailedOrgs = failures.orgs.length
  const repoCount = pluralize('repository', failures.totalRepoFailures, true)

  let innerText
  if (numberOfFailedOrgs <= 3) {
    const orgsText = pluralize('organization', numberOfFailedOrgs, false)
    const listOfOrgs = failures.orgs.map(({name}, index) => {
      let seperator
      if (index === numberOfFailedOrgs - 2) {
        seperator = ' and '
      } else if (index !== numberOfFailedOrgs - 1) {
        seperator = ', '
      }

      const href = settingsOrgSecurityProductsPath({org: name, q: 'config-status:failed'})
      return (
        <span key={name}>
          <PrimerLink inline href={href} target="_blank">
            {name}
          </PrimerLink>
          {seperator}
        </span>
      )
    })

    innerText = (
      <>
        Applying security configurations failed for {repoCount} in the following {orgsText}: {listOfOrgs}
      </>
    )
  } else {
    const orgCount = pluralize('organization', numberOfFailedOrgs, true)
    innerText = (
      <>
        {repoCount} across {orgCount} failed to apply.{' '}
        <PrimerLink
          as="button"
          onClick={() => {
            setShowFailedOrgDialog(true)
          }}
          className={styles.PrimerLink}
        >
          View list of failed organizations.
        </PrimerLink>
      </>
    )
  }
  return (
    <>
      {showFailedOrgDialog && <OrgFailuresDialog failures={failures} setShowFailedOrgDialog={setShowFailedOrgDialog} />}

      <Banner
        className="mb-4"
        data-testid="org-failures-banner"
        description={innerText}
        hideTitle
        title="Organization security configuration failures"
        variant="critical"
      />
    </>
  )
}

export default OrgFailuresBanner
