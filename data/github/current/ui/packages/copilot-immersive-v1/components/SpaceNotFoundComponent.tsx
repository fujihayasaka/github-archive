import {SingleSignOnBanner} from '@github-ui/single-sign-on-banner'
import {AlertIcon} from '@primer/octicons-react'

import styles from './SpaceNotFoundComponent.module.css'

export const SpaceNotFoundComponent = ({protectedOrganizations}: {protectedOrganizations?: string[]}) => {
  return (
    <>
      <div className={styles.container}>
        <AlertIcon className={styles.icon} />
        <h3>Space not found</h3>
        <p className={styles.description}>
          This URL may be incorrect, you&apos;re signed out of your organization, or the Space may have been deleted.
        </p>

        <div className={styles.banner}>
          {protectedOrganizations && (
            <SingleSignOnBanner
              protectedOrgs={protectedOrganizations}
              redirectURI={() =>
                `/search/refresh_blackbird_caches?return_to=${encodeURIComponent(window.location.href)}`
              }
            />
          )}
        </div>
      </div>
    </>
  )
}
