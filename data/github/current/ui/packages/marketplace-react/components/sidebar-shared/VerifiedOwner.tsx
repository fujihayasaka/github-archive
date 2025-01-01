import {Stack, Link} from '@primer/react'
import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import {VerifiedIcon} from '@primer/octicons-react'
import type {MarketplacePageTypes} from '../../types'

interface VerifiedOwnerProps {
  isVerifiedOwner: boolean
  pageType: MarketplacePageTypes
}

type VerifiedOwnerInformation = {
  verifiedOwnerText: string
  verifiedOwnerLink: string
  verifiedOwnerLinkText: string
}

export function VerifiedOwner(props: VerifiedOwnerProps) {
  const {isVerifiedOwner, pageType} = props

  function getVerifiedOwnerInformation(): VerifiedOwnerInformation {
    if (pageType === 'apps') {
      return {
        verifiedOwnerText:
          "GitHub has verified the publisher's identity, ownership of their domain, and compliance with ",
        verifiedOwnerLink:
          'https://docs.github.com/en/apps/github-marketplace/github-marketplace-overview/about-marketplace-badges',
        verifiedOwnerLinkText: 'other requirements',
      }
    } else if (pageType === 'actions') {
      return {
        verifiedOwnerText:
          'GitHub has manually verified the creator of the action as an official partner organization. For more info see ',
        verifiedOwnerLink:
          'https://docs.github.com/en/actions/sharing-automations/creating-actions/publishing-actions-in-github-marketplace#about-badges-in-github-marketplace',
        verifiedOwnerLinkText: 'About badges in GitHub Marketplace',
      }
    } else {
      return {
        verifiedOwnerText: '',
        verifiedOwnerLink: '',
        verifiedOwnerLinkText: '',
      }
    }
  }

  const {verifiedOwnerText, verifiedOwnerLink, verifiedOwnerLinkText} = getVerifiedOwnerInformation()

  return (
    <>
      {isVerifiedOwner && (
        <Stack gap={'condensed'} data-testid={'verified-owner'}>
          <div className="d-flex flex-items-center gap-2">
            <SidebarHeading title="Verified" htmlTag={'h2'} />
            <VerifiedIcon size={16} className="fgColor-accent" aria-label="Manually verified" />
          </div>
          <span>
            {verifiedOwnerText}
            <Link inline href={verifiedOwnerLink}>
              {verifiedOwnerLinkText}
            </Link>
            .
          </span>
        </Stack>
      )}
    </>
  )
}
