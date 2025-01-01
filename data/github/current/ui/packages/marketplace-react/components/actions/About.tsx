import {Link, Stack} from '@primer/react'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import {orgHovercardPath, userHovercardPath, ownerPath} from '@github-ui/paths'
import type {Repository} from '../../types'
import {VerifiedIcon} from '@primer/octicons-react'
import type {ActionListing} from '@github-ui/marketplace-common'

interface AboutProps {
  action: ActionListing
  repository: Repository
  sidebar?: boolean
}

export function About(props: AboutProps) {
  const {action, repository, sidebar} = props
  const {description, isVerifiedOwner} = action
  const {isOrganization, owner} = repository

  return (
    <Stack gap={'condensed'} data-testid={'about'}>
      {sidebar && <SidebarHeading title="About" htmlTag={'h2'} />}
      {description && <span>{description}</span>}
      <Stack wrap={'wrap'} direction={'horizontal'} gap={'condensed'}>
        {owner && (
          <div className={'color-fg-muted pr-1'}>
            <>
              {'By '}
              <Link
                href={ownerPath({owner})}
                data-hovercard-type={isOrganization ? 'organization' : 'user'}
                data-hovercard-url={isOrganization ? orgHovercardPath({owner}) : userHovercardPath({owner})}
              >
                {owner}
              </Link>
            </>
          </div>
        )}
        {isVerifiedOwner && !sidebar && (
          <div>
            <VerifiedIcon size={16} className="fgColor-accent" />
            <span className={'ml-2'}>Verified creator</span>
          </div>
        )}
      </Stack>
    </Stack>
  )
}
