import {IconButton} from '@primer/react'
import {CommentIcon} from '@primer/octicons-react'
import pluralize from 'pluralize'

export interface CampaignContactLinkProps {
  contactLink: string | null
  teamCount: number
  userCount: number
}

export function CampaignContactLink({contactLink, teamCount, userCount}: CampaignContactLinkProps) {
  if (!contactLink) {
    return null
  }

  // Pluralize needs a number to determine the plural form
  // but we want to pluralize even if the team number is 1
  const pluralizeManager = teamCount > 0 || userCount > 1 ? 2 : 1

  return (
    <span>
      <IconButton
        className="mx-1 v-align-middle"
        as="a"
        variant="invisible"
        icon={CommentIcon}
        href={contactLink}
        rel="noopener noreferrer"
        target="_blank"
        aria-label={`Contact campaign ${pluralize('manager', pluralizeManager)}`}
        size="small"
      />
    </span>
  )
}
