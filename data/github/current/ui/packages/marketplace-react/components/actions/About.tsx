import {Link, Stack, Truncate, Label} from '@primer/react'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import {orgHovercardPath, userHovercardPath, ownerPath} from '@github-ui/paths'
import {VerifiedIcon, TagIcon} from '@primer/octicons-react'
import styles from '../../marketplace.module.css'
import type {Repository, ReleaseData} from '../../types'
import type {ActionListing} from '@github-ui/marketplace-common'

interface AboutProps {
  action: ActionListing
  repository: Repository
  sidebar?: boolean
  releaseData: ReleaseData
}

export function About(props: AboutProps) {
  const {action, repository, sidebar, releaseData} = props
  const {description, isVerifiedOwner} = action
  const {isOrganization, owner} = repository
  const {selectedRelease, latestRelease} = releaseData
  const release = selectedRelease ? selectedRelease : latestRelease

  return (
    <Stack gap={'condensed'} data-testid={'about'}>
      {sidebar && <SidebarHeading title="About" htmlTag={'h2'} />}
      {description && <span>{description}</span>}

      <Stack gap={'condensed'} direction="horizontal">
        <TagIcon className={styles['marketplace-version-icon']} />
        <div className="min-width-0">
          <Stack gap={'condensed'} direction="horizontal">
            <Truncate inline title={release.tagName} maxWidth="none">
              <span>{release.tagName}</span>
            </Truncate>
            {release.tagName === latestRelease.tagName && (
              <Label variant="success" className="flex-shrink-0">
                Latest
              </Label>
            )}
            {release.isPrerelease && (
              <Label variant="severe" className="flex-shrink-0">
                Pre-release
              </Label>
            )}
          </Stack>
        </div>
      </Stack>

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
            <VerifiedIcon size={16} className="fgColor-accent" aria-label="Manually verified" />
            <span className={'ml-2'}>Verified creator</span>
          </div>
        )}
      </Stack>
    </Stack>
  )
}
