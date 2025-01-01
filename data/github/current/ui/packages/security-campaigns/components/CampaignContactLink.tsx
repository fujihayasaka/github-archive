import {IconButton} from '@primer/react'
import {CommentIcon} from '@primer/octicons-react'

export interface CampaignContactLinkProps {
  contactLink: string | null
}

export function CampaignContactLink({contactLink}: CampaignContactLinkProps) {
  if (!contactLink) {
    return null
  }

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
        aria-label="Contact campaign manager"
        size="small"
      />
    </span>
  )
}
