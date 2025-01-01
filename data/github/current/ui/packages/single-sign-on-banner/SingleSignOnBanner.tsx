import {ShieldLockIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Box, Flash, Link, type SxProp} from '@primer/react'
import type {Location} from 'react-router-dom'
import {useLocation} from 'react-router-dom'

import styles from './SingleSignOnBanner.module.css'
import {clsx} from 'clsx'

export function SingleSignOnBanner({
  className,
  portalContainerName,
  protectedOrgs,
  maxVisibleOrgNames = 3,
  redirectURI,
  useFullWidthStyle,
  forceWrap,
  sx,
}: {
  className?: string
  portalContainerName?: string
  protectedOrgs?: string[]
  maxVisibleOrgNames?: 0 | 3
  redirectURI?: (location: Location) => string
  useFullWidthStyle?: boolean
  forceWrap?: boolean
} & SxProp) {
  const location = useLocation()

  if (!protectedOrgs || protectedOrgs.length === 0) {
    return null
  }

  // If there are TONS of protected orgs, render them in a combined format
  const hiddenOrgsCount = Math.max(0, protectedOrgs.length - maxVisibleOrgNames)
  const visibleOrgNames = (function () {
    if (protectedOrgs.length === 1 || hiddenOrgsCount > 0) {
      return <b>{protectedOrgs.slice(0, maxVisibleOrgNames).join(', ')}</b>
    } else {
      return (
        <span>
          <b>{protectedOrgs.slice(0, protectedOrgs.length - 1).join(', ')}</b>
          {protectedOrgs.length > 2 && ','} and <b>{protectedOrgs[protectedOrgs.length - 1]}</b>
        </span>
      )
    }
  })()

  return (
    <Box sx={sx} className={className} data-testid="sso-banner">
      <div className={styles.Box}>
        <section aria-label="Single sign-on information">
          <Flash
            sx={{
              borderRadius: useFullWidthStyle ? 0 : 2,
              borderWidth: useFullWidthStyle ? '1px 0' : 1,
            }}
            className={styles.Flash}
          >
            {protectedOrgs.length === 1 ? (
              <div>
                <ShieldLockIcon />
                <Link
                  inline
                  href={`/orgs/${protectedOrgs[0]}/sso?return_to=${encodedRedirectURI({location, redirectURI})}`}
                >
                  Single sign-on
                </Link>{' '}
                to see results in the <b>{protectedOrgs[0]}</b> organization.
              </div>
            ) : (
              <div className={styles.Box_1}>
                <ShieldLockIcon className={styles.Octicon} />
                <div className={clsx(styles.Box_2, forceWrap && styles.ForceWrap)}>
                  <p className={styles.Paragraph}>
                    Single sign-on to see results in {hiddenOrgsCount === 0 && 'the '}
                    {maxVisibleOrgNames > 0 && <>{visibleOrgNames} </>}
                    {hiddenOrgsCount > 0 && (
                      <>
                        {maxVisibleOrgNames > 0 && 'and '}
                        {hiddenOrgsCount} other{' '}
                      </>
                    )}
                    {protectedOrgs.length > 1 && hiddenOrgsCount !== 1 ? 'organizations' : 'organization'}.
                  </p>
                  <div style={{flexShrink: 0}}>
                    <SingleSignOnButton
                      portalContainerName={portalContainerName}
                      protectedOrgs={protectedOrgs}
                      redirectURI={redirectURI}
                    />
                  </div>
                </div>
              </div>
            )}
          </Flash>
        </section>
      </div>
    </Box>
  )
}
function SingleSignOnButton({
  portalContainerName,
  protectedOrgs,
  redirectURI,
}: {
  portalContainerName?: string
  protectedOrgs: string[]
  redirectURI?: (location: Location) => string
}) {
  const location = useLocation()
  return (
    <ActionMenu>
      <ActionMenu.Button size="small">Select an organization</ActionMenu.Button>
      <ActionMenu.Overlay portalContainerName={portalContainerName}>
        <ActionList>
          {protectedOrgs.map(org => (
            <ActionList.Item
              key={`org-${org}`}
              onSelect={() =>
                (window.location.href = `/orgs/${encodeURIComponent(org)}/sso?return_to=${encodedRedirectURI({
                  location,
                  redirectURI,
                })}`)
              }
            >
              {org}
            </ActionList.Item>
          ))}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

function encodedRedirectURI({
  location,
  redirectURI,
}: {
  location: Location
  redirectURI?: (location: Location) => string
}) {
  return encodeURIComponent(redirectURI ? redirectURI(location) : location.pathname + location.search + location.hash)
}
