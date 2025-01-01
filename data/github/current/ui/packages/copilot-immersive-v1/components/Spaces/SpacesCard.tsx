import type {IndexCustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getCopilotSpacePath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {Card} from '@github-ui/pacer/Card'
import type {IconColor} from '@github-ui/pacer/Icon'
import {ClockIcon, LockIcon, OrganizationIcon, PeopleIcon, PersonIcon, PlusIcon} from '@primer/octicons-react'
import {RelativeTime} from '@primer/react'

import {getVisibilityText} from '../../utils/visibility-helpers'
import SpacesIcon from '../Icons/SpacesIcon'
import {CopilotSpacesMenu} from './SpaceMenu'
import styles from './SpacesCard.module.css'

interface NewSpaceCardProps {
  onClick: () => void
}

export function NewSpacesCard({onClick}: NewSpaceCardProps) {
  return (
    <Card onClick={onClick}>
      <Card.Icon icon={PlusIcon} />
      <Card.Heading>Create a new space</Card.Heading>
      <Card.Description>Add attachments, repositories, and more.</Card.Description>
    </Card>
  )
}

interface SpaceCardProps {
  copilotSpace: IndexCustomCopilot
  spaceVisibilityEnabled: boolean
  onDelete: () => Promise<void>
  onClick: () => void
}

export function SpacesCard({copilotSpace, spaceVisibilityEnabled, onDelete, onClick}: SpaceCardProps) {
  const OwnerIcon = copilotSpace.ownerIsOrg ? OrganizationIcon : PersonIcon
  const VisibilityIcon = copilotSpace.visibility === 'org_public' ? PeopleIcon : LockIcon
  const visibilityText = getVisibilityText(copilotSpace.visibility)

  return (
    <Card
      key={copilotSpace.owner ? `${copilotSpace.owner}/${copilotSpace.id}` : copilotSpace.id}
      href={getCopilotSpacePath(copilotSpace)}
      onClick={onClick}
    >
      <Card.Icon icon={SpacesIcon} color={copilotSpace.iconColor as IconColor} />
      <Card.Heading>{copilotSpace.name}</Card.Heading>
      <Card.Description>{copilotSpace.description}</Card.Description>
      <Card.Menu>
        <CopilotSpacesMenu copilot={copilotSpace} onDelete={onDelete} />
      </Card.Menu>
      <Card.Metadata>
        {spaceVisibilityEnabled ? (
          <div className={styles.metadata}>
            <div className={styles.metadataItem}>
              <OwnerIcon />
              {copilotSpace.owner}
            </div>
            <div className={styles.metadataItem}>
              <VisibilityIcon />
              {visibilityText}
            </div>
          </div>
        ) : (
          <div className={styles.metadata}>
            <div className={styles.metadataItem}>
              <ClockIcon />
              <RelativeTime format="micro" prefix="" date={new Date(copilotSpace.updatedAt)} />
            </div>
          </div>
        )}
      </Card.Metadata>
    </Card>
  )
}
