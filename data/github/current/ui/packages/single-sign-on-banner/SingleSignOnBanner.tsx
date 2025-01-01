import {ShieldLockIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Box, Flash, Link, type SxProp} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import type {Location} from 'react-router-dom'
import {useLocation} from 'react-router-dom'

export function SingleSignOnBanner({
  portalContainerName,
  protectedOrgs,
  redirectURI,
  isDisplayedInSelectPanel,
  sx,
}: {
  portalContainerName?: string
  protectedOrgs?: string[]
  redirectURI?: (location: Location) => string
  isDisplayedInSelectPanel?: boolean
} & SxProp) {
  const location = useLocation()

  if (!protectedOrgs || protectedOrgs.length === 0) {
    return null
  }

  // If there are TONS of protected orgs, render them in a combined format
  let visibleOrgNames = <b>{protectedOrgs.slice(0, 3).join(', ')}</b>

  if (protectedOrgs.length === 2) {
    visibleOrgNames = (
      <span>
        <b>{protectedOrgs[0]}</b> and <b>{protectedOrgs[1]}</b>
      </span>
    )
  }

  if (protectedOrgs.length === 3) {
    visibleOrgNames = (
      <span>
        <b>{protectedOrgs.slice(0, 2).join(', ')}</b>, and <b>{protectedOrgs[2]}</b>
      </span>
    )
  }

  return (
    <Box sx={sx} data-testid="sso-banner">
      <Box sx={{fontSize: 1}}>
        <section aria-label="Single sign on information">
          <Flash
            sx={{
              p: 3,
              borderRadius: isDisplayedInSelectPanel ? 0 : 2,
              borderWidth: isDisplayedInSelectPanel ? '1px 0' : 1,
              borderStyle: 'solid',
              borderColor: 'accent.muted',
              fontSize: 1,
            }}
          >
            {protectedOrgs.length === 1 ? (
              <div>
                <Octicon icon={ShieldLockIcon} />
                <Link
                  inline
                  href={`/orgs/${protectedOrgs[0]}/sso?return_to=${encodedRedirectURI({location, redirectURI})}`}
                >
                  Single sign-on
                </Link>
                &nbsp;to see results in the <b>{protectedOrgs[0]}</b> organization.
              </div>
            ) : (
              <Box
                sx={{
                  display: 'flex',
                  alignItems: 'baseline',
                  gap: 2,
                  '& svg': {
                    marginRight: '0 !important',
                  },
                }}
              >
                <Octicon sx={{position: 'relative', top: '3px'}} icon={ShieldLockIcon} />
                <Box
                  sx={{display: 'flex', alignItems: 'baseline', gap: [0, 2], flexWrap: ['wrap', 'nowrap'], flexGrow: 1}}
                >
                  <Box as="p" sx={{marginBottom: 0}}>
                    Single sign on to see results in the {visibleOrgNames}{' '}
                    {protectedOrgs.length > 3 ? `and ${protectedOrgs.length - 3} other ` : ''}
                    {protectedOrgs.length > 1 ? 'organizations' : 'organization'}.
                  </Box>
                  <div>
                    <SingleSignOnButton
                      portalContainerName={portalContainerName}
                      protectedOrgs={protectedOrgs}
                      redirectURI={redirectURI}
                    />
                  </div>
                </Box>
              </Box>
            )}
          </Flash>
        </section>
      </Box>
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
                (window.location.href = `/orgs/${org}/sso?return_to=${encodedRedirectURI({location, redirectURI})}`)
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
