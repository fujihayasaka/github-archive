import {Stack} from '@primer/react'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import {VerifiedIcon} from '@primer/octicons-react'

interface VerifiedOwnerProps {
  isVerifiedOwner: boolean
}

export function VerifiedOwner(props: VerifiedOwnerProps) {
  const {isVerifiedOwner} = props

  return (
    <>
      {isVerifiedOwner && (
        <Stack gap={'condensed'} data-testid={'verified-owner'}>
          <div className="d-flex flex-items-center gap-2">
            <SidebarHeading title="Verified" htmlTag={'h2'} />
            <VerifiedIcon size={16} className="fgColor-accent" />
          </div>
          <span>
            GitHub has verified the publisher&#39;s identity, ownership of the domain, and compliance with{' '}
            <a href="https://docs.github.com/en/apps/github-marketplace/github-marketplace-overview/about-marketplace-badges">
              {'other requirements'}
            </a>
            .
          </span>
        </Stack>
      )}
    </>
  )
}
