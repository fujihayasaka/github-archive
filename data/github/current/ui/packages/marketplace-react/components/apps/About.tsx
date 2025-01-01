import {Stack, Link} from '@primer/react'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import {orgHovercardPath, userHovercardPath, ownerPath} from '@github-ui/paths'
import {DownloadIcon} from '@primer/octicons-react'
import type {AppListing} from '@github-ui/marketplace-common'

interface AboutProps {
  app: AppListing
  sidebar?: boolean
}

export function About(props: AboutProps) {
  const {app, sidebar} = props
  const {shortDescription, ownerLogin, ownerType} = app
  const isOwnerOrganization = ownerType === 'Organization'
  const isOwnerUser = ownerType === 'User'

  return (
    <Stack gap={'condensed'} data-testid={'about'}>
      {sidebar && <SidebarHeading title="About" htmlTag={'h2'} />}
      {shortDescription && <span>{shortDescription}</span>}
      <Stack wrap={'wrap'} direction={'horizontal'} gap={'condensed'}>
        {ownerLogin && (
          <div className={'color-fg-muted pr-1'}>
            <>
              {'By '}
              {isOwnerOrganization || isOwnerUser ? (
                <Link
                  href={ownerPath({owner: ownerLogin})}
                  data-hovercard-type={isOwnerOrganization ? 'organization' : 'user'}
                  data-hovercard-url={
                    isOwnerOrganization ? orgHovercardPath({owner: ownerLogin}) : userHovercardPath({owner: ownerLogin})
                  }
                >
                  {ownerLogin}
                </Link>
              ) : (
                <Link href={ownerPath({owner: ownerLogin})}>{ownerLogin}</Link>
              )}
            </>
          </div>
        )}
        <div>
          <DownloadIcon className="mr-1 fgColor-muted" />
          <span className="text-bold">{app.installationCount.toLocaleString()}&nbsp;</span>
          <span className="fgColor-muted">install{app.installationCount === 1 ? '' : 's'}</span>
        </div>
      </Stack>
    </Stack>
  )
}
