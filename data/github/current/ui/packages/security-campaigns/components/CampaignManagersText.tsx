import {useCallback, useState} from 'react'
import {ActionList, Button, Dialog, Link, Text, type SxProp} from '@primer/react'
import {teamHovercardPath, teamPath, userHovercardPath} from '@github-ui/paths'
import {GitHubAvatar} from '@github-ui/github-avatar'
import type {Team} from '../types/team'
import type {User} from '../types/user'

export interface CampaignManagersTextProps {
  managers: User[]
  teamManagers: Team[]
}

export function CampaignManagersText({managers, teamManagers, sx}: CampaignManagersTextProps & SxProp) {
  const [isOpen, setIsOpen] = useState(false)
  const handleOpen = useCallback(() => setIsOpen(true), [])
  const handleClose = useCallback(() => setIsOpen(false), [])

  const allManagers: Array<User | Team> = [...teamManagers, ...managers].sort((a, b) => {
    const aLoginOrSlug = 'login' in a ? a.login : a.slug
    const bLoginOrSlug = 'login' in b ? b.login : b.slug

    return aLoginOrSlug.localeCompare(bLoginOrSlug, 'en-US')
  })
  const firstManager = allManagers[0]

  if (allManagers.length === 0 || !firstManager) {
    return null
  }

  const renderManagerLink = (manager: User | Team) => {
    // login field is unique to User type
    if ('login' in manager) {
      return (
        <Link
          key={`user-manager-${manager.id}`}
          href={`/${manager.login}`}
          sx={{color: 'fg.default', fontWeight: 'bold'}}
          data-hovercard-url={userHovercardPath({owner: manager.login})}
        >
          {manager.login}
        </Link>
      )
    }

    return (
      <Link
        key={`team-manager-${manager.id}`}
        href={teamPath({owner: manager.organizationLogin, team: manager.slug})}
        sx={{color: 'fg.default', fontWeight: 'bold'}}
        data-hovercard-url={teamHovercardPath({owner: manager.organizationLogin, team: manager.slug})}
      >
        {manager.slug}
      </Link>
    )
  }

  const renderManagerDialogRow = (manager: User | Team) => {
    // login field is unique to User type
    if ('login' in manager) {
      return (
        <ActionList.LinkItem key={`user-manager-${manager.id}`} href={`/${manager.login}`}>
          <ActionList.LeadingVisual>
            <GitHubAvatar src={manager.avatarUrl} />
          </ActionList.LeadingVisual>
          {manager.login}
          {manager.name && <ActionList.Description>{manager.name}</ActionList.Description>}
        </ActionList.LinkItem>
      )
    }

    return (
      <ActionList.LinkItem
        key={`team-manager-${manager.id}`}
        href={teamPath({owner: manager.organizationLogin, team: manager.slug})}
      >
        <ActionList.LeadingVisual>
          <GitHubAvatar src={manager.avatarUrl} square />
        </ActionList.LeadingVisual>
        {manager.slug}
        <ActionList.Description>{manager.name}</ActionList.Description>
      </ActionList.LinkItem>
    )
  }

  if (allManagers.length <= 2) {
    return (
      <Text sx={sx}>
        Managed by {renderManagerLink(firstManager)}
        {allManagers[1] && <> and {renderManagerLink(allManagers[1])}</>}
      </Text>
    )
  }

  return (
    <Text sx={sx}>
      Managed by {renderManagerLink(firstManager)}{' '}
      <Button variant="link" sx={{color: 'fg.default', fontWeight: 'bold'}} onClick={handleOpen}>
        and {allManagers.length - 1} others
      </Button>
      {isOpen && (
        <Dialog
          title="Campaign managers"
          subtitle="These users are the campaign contacts."
          onClose={handleClose}
          width="small"
          renderBody={() => <ActionList>{allManagers.map(manager => renderManagerDialogRow(manager))}</ActionList>}
        />
      )}
    </Text>
  )
}
