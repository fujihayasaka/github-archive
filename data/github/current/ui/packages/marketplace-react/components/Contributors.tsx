import {Link, Stack} from '@primer/react'
import {GitHubAvatar} from '@github-ui/github-avatar'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import {userHovercardPath, repoContributorsPath, ownerPath} from '@github-ui/paths'
import type {Repository} from '../types'

interface ContributorsProps {
  repository: Repository
}

export function Contributors(props: ContributorsProps) {
  const {repository} = props
  const {contributorsCount, topContributorsData, owner, name} = repository
  const remainingContributors = contributorsCount - topContributorsData.length

  return (
    <>
      {contributorsCount > 0 && owner && name && (
        <Stack gap={'condensed'} data-testid={'contributors'}>
          <SidebarHeading
            title="Contributors"
            count={contributorsCount}
            htmlTag={'h2'}
            link={repoContributorsPath({ownerLogin: owner, name})}
          />
          <Stack direction={'horizontal'} gap={'condensed'} wrap={'wrap'}>
            {topContributorsData.map(contributor => (
              <Link key={contributor.alt} href={ownerPath({owner: contributor.displayLogin})}>
                <GitHubAvatar
                  src={contributor.src}
                  alt={contributor.alt}
                  size={32}
                  data-hovercard-type="user"
                  data-hovercard-url={userHovercardPath({owner: contributor.displayLogin})}
                />
              </Link>
            ))}
          </Stack>
          {remainingContributors > 0 && (
            <Link href={repoContributorsPath({ownerLogin: owner, name})}>+ {remainingContributors} contributors</Link>
          )}
        </Stack>
      )}
    </>
  )
}
