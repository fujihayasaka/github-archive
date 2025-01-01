import {ActionList, AvatarStack} from '@primer/react'
import {SelectPanel} from '@primer/react/experimental'
import {GitHubAvatar} from '@github-ui/github-avatar'
import React, {useCallback, useMemo} from 'react'
import pluralize from 'pluralize'
import {TriangleDownIcon} from '@primer/octicons-react'
import type {Team} from '../types/team'
import {securityCampaignOrgManagersPath} from '@github-ui/paths'

import styles from './SecurityCampaignManagersSelect.module.css'
import type {User} from '../types/user'
import {useCampaignManagersQuery} from '../hooks/use-campaign-managers-query'

export type SecurityCampaignManagersSelectProps = {
  users: User[]
  onChangeUsers: (users: User[]) => void
  teams: Team[]
  onChangeTeams: (teams: Team[]) => void
  organizationLogin: string
  maxManagers: number
  disabled?: boolean

  'aria-labelledby'?: string
}

export function SecurityCampaignManagersSelect({
  users,
  onChangeUsers,
  teams,
  onChangeTeams,
  organizationLogin,
  maxManagers,
  disabled,
}: SecurityCampaignManagersSelectProps) {
  const {data} = useCampaignManagersQuery(securityCampaignOrgManagersPath({org: organizationLogin}), !disabled)

  const potentialUserManagers = useMemo(() => {
    const managers = [...(data?.managers ?? [])]

    for (const item of users) {
      if (item && !managers.some(manager => manager.id === item.id)) {
        managers.push(item)
      }
    }

    return managers
  }, [data, users])
  const potentialTeamManagers = useMemo(() => {
    const managers = [...(data?.teamManagers ?? [])]

    for (const item of teams) {
      if (item && !managers.some(manager => manager.id === item.id)) {
        managers.push(item)
      }
    }

    return managers
  }, [data, teams])

  const [filter, setFilter] = React.useState('')

  const onSearchInputChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setFilter(event.target.value)
    },
    [setFilter],
  )

  const filteredUserItems = potentialUserManagers.filter(item =>
    item.login.toLowerCase().startsWith(filter.toLowerCase()),
  )
  const filteredTeamItems = potentialTeamManagers.filter(item =>
    item.slug.toLowerCase().startsWith(filter.toLowerCase()),
  )

  const selectedUserItems = useMemo(() => {
    const usersIds = users.map(item => item.id)

    return potentialUserManagers.filter(item => usersIds.includes(item.id))
  }, [potentialUserManagers, users])
  const selectedUserItemIds = selectedUserItems.map(item => item.id)

  const selectedTeamItems = useMemo(() => {
    const teamIds = teams.map(item => item.id)

    return potentialTeamManagers.filter(item => teamIds.includes(item.id))
  }, [potentialTeamManagers, teams])
  const selectedTeamItemIds = selectedTeamItems.map(item => item.id)

  const handleSelectedUserChange = useCallback(
    (newUsers: typeof potentialUserManagers | undefined) => {
      const ids = newUsers?.map(item => item.id) ?? []

      const newUserManagers = potentialUserManagers.filter(manager => ids.includes(manager.id))
      // Sort the users by user login
      newUserManagers.sort((a, b) => a.login.localeCompare(b.login, 'en'))

      onChangeUsers(newUserManagers)
    },
    [onChangeUsers, potentialUserManagers],
  )

  const handleUserItemClick = useCallback(
    (item: (typeof potentialUserManagers)[number]) => {
      if (selectedUserItemIds.includes(item.id)) {
        handleSelectedUserChange(selectedUserItems.filter(selectedItem => selectedItem.id !== item.id))
      } else {
        handleSelectedUserChange([...selectedUserItems, item])
      }
    },
    [handleSelectedUserChange, selectedUserItemIds, selectedUserItems],
  )

  const handleSelectedTeamChange = useCallback(
    (newTeams: typeof potentialTeamManagers | undefined) => {
      const ids = newTeams?.map(item => item.id) ?? []

      const newTeamManagers = potentialTeamManagers.filter(manager => ids.includes(manager.id))
      // Sort the teams by team slug
      newTeamManagers.sort((a, b) => a.slug.localeCompare(b.slug, 'en'))

      onChangeTeams(newTeamManagers)
    },
    [onChangeTeams, potentialTeamManagers],
  )

  const handleTeamItemClick = useCallback(
    (item: (typeof potentialTeamManagers)[number]) => {
      if (selectedTeamItemIds.includes(item.id)) {
        handleSelectedTeamChange(selectedTeamItems.filter(selectedItem => selectedItem.id !== item.id))
      } else {
        handleSelectedTeamChange([...selectedTeamItems, item])
      }
    },
    [handleSelectedTeamChange, selectedTeamItemIds, selectedTeamItems],
  )

  const sortedManagers = useMemo(() => {
    const result: Array<User | Team> = [...selectedUserItems, ...selectedTeamItems].sort((a, b) => {
      const aLoginOrSlug = 'login' in a ? a.login : a.slug
      const bLoginOrSlug = 'login' in b ? b.login : b.slug

      return aLoginOrSlug.localeCompare(bLoginOrSlug, 'en-US')
    })

    return result
  }, [selectedTeamItems, selectedUserItems])

  const sortedFilteredManagers = useMemo(() => {
    const result: Array<User | Team> = [...filteredUserItems, ...filteredTeamItems].sort((a, b) => {
      const aLoginOrSlug = 'login' in a ? a.login : a.slug
      const bLoginOrSlug = 'login' in b ? b.login : b.slug

      return aLoginOrSlug.localeCompare(bLoginOrSlug, 'en-US')
    })

    return result
  }, [filteredTeamItems, filteredUserItems])

  const renderManagerActionListItems = () => {
    return sortedFilteredManagers.map(manager => {
      if ('login' in manager) {
        return (
          <ActionList.Item
            key={`user-${manager.id}`}
            onSelect={() => handleUserItemClick(manager)}
            selected={selectedUserItemIds.includes(manager.id)}
            aria-labelledby={`manager-action-list-user-${manager.id}`}
            disabled={
              disabled ||
              (!selectedUserItemIds.includes(manager.id) &&
                selectedUserItems.length + selectedTeamItems.length >= maxManagers)
            }
          >
            <ActionList.LeadingVisual>
              <GitHubAvatar size={16} src={manager.avatarUrl} alt="User avatar" className={styles.gitHubAvatar} />
            </ActionList.LeadingVisual>
            <span id={`manager-action-list-user-${manager.id}`}>{manager.login}</span>
            {manager.name && <ActionList.Description>{manager.name}</ActionList.Description>}
          </ActionList.Item>
        )
      }

      return (
        <ActionList.Item
          key={`team-${manager.id}`}
          onSelect={() => handleTeamItemClick(manager)}
          selected={selectedTeamItemIds.includes(manager.id)}
          aria-labelledby={`manager-action-list-team-${manager.id}`}
          disabled={
            disabled ||
            (!selectedTeamItemIds.includes(manager.id) &&
              selectedUserItems.length + selectedTeamItems.length >= maxManagers)
          }
        >
          <ActionList.LeadingVisual>
            <GitHubAvatar size={16} src={manager.avatarUrl} alt="Team avatar" square className={styles.gitHubAvatar} />
          </ActionList.LeadingVisual>
          <span id={`manager-action-list-team-${manager.id}`}>{manager.slug}</span>
          {manager.name && <ActionList.Description>{manager.name}</ActionList.Description>}
        </ActionList.Item>
      )
    })
  }

  const getFirstManagerDisplayName = (): string => {
    const firstManager = sortedManagers[0]
    if (!firstManager) {
      return ''
    }

    if ('login' in firstManager) {
      return firstManager.login
    } else if (firstManager.organizationLogin) {
      return `${firstManager.organizationLogin}/${firstManager.slug}`
    }

    return firstManager.slug
  }

  const renderTitle = (): string => {
    if (disabled) {
      let result = `@${getFirstManagerDisplayName()}`
      if (sortedManagers.length > 1) {
        result += ` and ${sortedManagers.length - 1} ${pluralize('other', sortedManagers.length - 1)}`
      }

      return result
    }

    return 'Select campaign managers'
  }

  return (
    // eslint-disable-next-line primer-react/no-system-props
    <SelectPanel
      title={renderTitle()}
      maxHeight="medium"
      selectionVariant="multiple"
      onCancel={() => setFilter('')}
      onSubmit={() => setFilter('')}
      onClearSelection={
        disabled
          ? undefined
          : () => {
              handleSelectedUserChange([])
              handleSelectedTeamChange([])
            }
      }
    >
      <SelectPanel.Button trailingAction={TriangleDownIcon}>
        {sortedManagers.length > 0 ? (
          <div className={styles.avatarStackContainer}>
            <AvatarStack disableExpand className={styles.avatarStack}>
              {sortedManagers.map(manager =>
                'login' in manager ? (
                  <GitHubAvatar key={`user-${manager.id}`} size={16} src={manager.avatarUrl} alt="User avatar" />
                ) : (
                  <GitHubAvatar key={`team-${manager.id}`} size={16} src={manager.avatarUrl} alt="Team avatar" square />
                ),
              )}
            </AvatarStack>
            <div className={styles.avatarStackText}>
              @{getFirstManagerDisplayName()}
              {sortedManagers.length > 1 && (
                <>
                  {' '}
                  and {sortedManagers.length - 1} {pluralize('other', sortedManagers.length - 1)}
                </>
              )}
            </div>
          </div>
        ) : (
          'Select managers'
        )}
      </SelectPanel.Button>
      <SelectPanel.Header>
        <SelectPanel.SearchInput onChange={onSearchInputChange} placeholder="Search" />
      </SelectPanel.Header>
      {sortedManagers.length >= maxManagers && (
        <SelectPanel.Message variant="warning" size="inline">
          You have reached the limit of {maxManagers} campaign managers.
        </SelectPanel.Message>
      )}
      {sortedFilteredManagers.length === 0 ? (
        <SelectPanel.Message variant="empty" title={`No users or teams found for "${filter}"`}>
          Try a different search term
        </SelectPanel.Message>
      ) : (
        <ActionList selectionVariant="multiple">{renderManagerActionListItems()}</ActionList>
      )}
    </SelectPanel>
  )
}
